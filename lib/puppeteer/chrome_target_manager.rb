class Puppeteer::ChromeTargetManager
  include Puppeteer::EventCallbackable

  def initialize(connection:, target_factory:, target_filter_callback:)
    @discovered_targets_by_target_id = {}
    @attached_targets_by_target_id = {}
    @attached_targets_by_session_id = {}
    @ignored_targets = Set.new
    @target_ids_for_init = Set.new

    @connection = connection
    @target_filter_callback = target_filter_callback
    @target_factory = target_factory
    @target_interceptors = {}
    @initialize_promise = resolvable_future

    @connection_event_listeners = []
    @connection_event_listeners << @connection.add_event_listener(
      'Target.targetCreated',
      &method(:handle_target_created)
    )
    @connection_event_listeners << @connection.add_event_listener(
      'Target.targetDestroyed',
      &method(:handle_target_destroyed)
    )
    @connection_event_listeners << @connection.add_event_listener(
      'Target.targetInfoChanged',
      &method(:handle_target_info_changed)
    )
    @connection_event_listeners << @connection.add_event_listener(
      'sessiondetached',
      &method(:handle_session_detached)
    )

    setup_attachment_listeners(@connection)
    @connection.async_send_message('Target.setDiscoverTargets', {
      discover: true,
      filter: [
        { type: 'tab', exclude: true },
        {},
      ],
    })
  end

  def init
    @discovered_targets_by_target_id.each do |target_id, target_info|
      if @target_filter_callback.call(target_info)
        @target_ids_for_init << target_id
      end
    end
    @connection.send_message('Target.setAutoAttach', {
      waitForDebuggerOnStart: true,
      flatten: true,
      autoAttach: true,
    })
    @initialize_promise.value!
  end

  def dispose
    @connection.remove_event_listener(*@connection_event_listeners)
    remove_attachment_listeners(@connection)
  end

  def available_targets
    @attached_targets_by_target_id
  end

  def add_target_interceptor(client, interceptor)
    interceptors = @target_interceptors[client] || []
    interceptors << interceptor
    @target_interceptors[client] = interceptors
  end

  def remove_target_interceptor(client, interceptor)
    @target_interceptors[client]&.delete_if { |current| current == interceptor }
  end

  private def setup_attachment_listeners(session)
    @attachment_listener_ids ||= {}
    @attachment_listener_ids[session] ||= []

    @attachment_listener_ids[session] << session.add_event_listener('Target.attachedToTarget') do |event|
      handle_attached_to_target(session, event)
    end

    @attachment_listener_ids[session] << session.add_event_listener('Target.detachedFromTarget') do |event|
      handle_detached_from_target(session, event)
    end
  end

  private def remove_attachment_listeners(session)
    return unless @attachment_listener_ids
    listener_ids = @attachment_listener_ids.delete(session)
    return if !listener_ids || listener_ids.empty?
    session.remove_event_listener(*listener_ids)
  end

  private def handle_session_detached(session)
    remove_attachment_listeners(session)
    @target_interceptors.delete(session)
  end

  private def handle_target_created(event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    @discovered_targets_by_target_id[target_info.target_id] = target_info

    emit_event(TargetManagerEmittedEvents::TargetDiscovered, target_info)

    # The connection is already attached to the browser target implicitly,
    # therefore, no new CDPSession is created and we have special handling
    # here.
    if target_info.type == 'browser' && target_info.attached
      return if @attached_targets_by_target_id[target_info.target_id]

      target = @target_factory.call(target_info, nil)
      @attached_targets_by_target_id[target_info.target_id] = target
    end

    if target_info.type == 'shared_worker'
      # Special case (https://crbug.com/1338156): currently, shared_workers
      # don't get auto-attached. This should be removed once the auto-attach
      # works.
      @connection.create_session(target_info)
    end
  end

  private def handle_target_destroyed(event)
    target_id = event['targetId']
    target_info = @discovered_targets_by_target_id.delete(target_id)
    finish_initialization_if_ready(target_id)

    if target_info.type == 'service_worker' && @attached_targets_by_target_id.has_key?(target_id)
      # Special case for service workers: report TargetGone event when
      # the worker is destroyed.
      target = @attached_targets_by_target_id.delete(target_id)
      emit_event(TargetManagerEmittedEvents::TargetGone, target)
    end
  end

  private def handle_target_info_changed(event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    @discovered_targets_by_target_id[target_info.target_id] = target_info

    if @ignored_targets.include?(target_info.target_id) || !@attached_targets_by_target_id.has_key?(target_info.target_id) || !target_info.attached
      return
    end
    original_target = @attached_targets_by_target_id[target_info.target_id]
    emit_event(TargetManagerEmittedEvents::TargetChanged, original_target, target_info)
  end

  class SessionNotCreatedError < StandardError ; end

  private def handle_attached_to_target(parent_session, event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    session_id = event['sessionId']
    session = @connection.session(session_id)
    unless session
      raise SessionNotCreatedError.new("Session #{session_id} was not created.")
    end

    silent_detach = -> {
      begin
        session.send_message('Runtime.runIfWaitingForDebugger')
      rescue => err
        Logger.new($stderr).warn(err)
      end

      # We don't use `session.detach()` because that dispatches all commands on
      # the connection instead of the parent session.
      begin
        parent_session.send_message('Target.detachFromTarget', {
          sessionId: session.id,
        })
      rescue => err
        Logger.new($stderr).warn(err)
      end
    }

    # Special case for service workers: being attached to service workers will
    # prevent them from ever being destroyed. Therefore, we silently detach
    # from service workers unless the connection was manually created via
    # `page.worker()`. To determine this, we use
    # `this.#connection.isAutoAttached(targetInfo.targetId)`. In the future, we
    # should determine if a target is auto-attached or not with the help of
    # CDP.
    if target_info.type == 'service_worker' && @connection.auto_attached?(target_info.target_id)
      finish_initialization_if_ready(target_info.target_id)
      silent_detach.call
      if parent_session.is_a?(Puppeteer::CDPSession)
        target = @target_factory.call(target_info, parent_session)
        @attached_targets_by_target_id[target_info.target_id] = target
        emit_event(TargetManagerEmittedEvents::TargetAvailable, target)
      end

      return
    end

    unless @target_filter_callback.call(target_info)
      @ignored_targets << target_info.target_id
      finish_initialization_if_ready(target_info.target_id)
      silent_detach.call

      return
    end

    target = @attached_targets_by_target_id[target_info.target_id] || @target_factory.call(target_info, session)
    setup_attachment_listeners(session)

    @attached_targets_by_target_id[target_info.target_id] ||= target
    @attached_targets_by_session_id[session.id] = target

    @target_interceptors[parent_session]&.each do |interceptor|
      if parent_session.is_a?(Puppeteer::Connection)
        interceptor.call(target, nil)
      else
        # Sanity check: if parent session is not a connection, it should be
        # present in #attachedTargetsBySessionId.
        attached_target = @attached_targets_by_session_id[parent_session.id]
        unless attached_target
          raise "No target found for the parent session: #{parent_session.id}"
        end
        interceptor.call(target, attached_target)
      end
    end

    @target_ids_for_init.delete(target.target_id)
    future { emit_event(TargetManagerEmittedEvents::TargetAvailable, target) }

    if @target_ids_for_init.empty?
      @initialize_promise.fulfill(nil) unless @initialize_promise.resolved?
    end

    future do
      # TODO: the browser might be shutting down here. What do we do with the error?
      await_all(
        session.async_send_message('Target.setAutoAttach', {
          waitForDebuggerOnStart: true,
          flatten: true,
          autoAttach: true,
        }),
        session.async_send_message('Runtime.runIfWaitingForDebugger'),
      )
    rescue => err
      Logger.new($stderr).warn(err)
    end
  end

  private def finish_initialization_if_ready(target_id)
    @target_ids_for_init.delete(target_id)
    if @target_ids_for_init.empty?
      @initialize_promise.fulfill(nil) unless @initialize_promise.resolved?
    end
  end

  private def handle_detached_from_target(parent_session, event)
    session_id = event['sessionId']
    target = @attached_targets_by_session_id.delete(session_id)
    return unless target
    @attached_targets_by_target_id.delete(target.target_id)
    emit_event(TargetManagerEmittedEvents::TargetGone, target)
  end
end
