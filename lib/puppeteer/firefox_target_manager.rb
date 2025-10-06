# FirefoxTargetManager implements target management using
# `Target.setDiscoverTargets` without using auto-attach. It, therefore, creates
# targets that lazily establish their CDP sessions.
#
# Although the approach is potentially flaky, there is no other way for Firefox
# because Firefox's CDP implementation does not support auto-attach.
#
# Firefox does not support targetInfoChanged and detachedFromTarget events:
# - https://bugzilla.mozilla.org/show_bug.cgi?id=1610855
# - https://bugzilla.mozilla.org/show_bug.cgi?id=1636979
class Puppeteer::FirefoxTargetManager
  include Puppeteer::EventCallbackable

  def initialize(connection:, target_factory:, target_filter_callback:)
    @discovered_targets_by_target_id = {}
    @available_targets_by_target_id = {}
    @available_targets_by_session_id = {}
    @ignored_targets = Set.new
    @target_ids_for_init = Set.new

    @connection = connection
    @target_filter_callback = target_filter_callback
    @target_factory = target_factory
    @target_interceptors = {}
    @initialize_promise = Concurrent::Promises.resolvable_future

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
      'sessiondetached',
      &method(:handle_session_detached)
    )

    setup_attachment_listeners(@connection)
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
  end

  private def handle_session_detached(session)
    remove_session_listeners(session)
    @target_interceptors.delete(session)
  end

  private def remove_session_listeners(session)
    listener_ids = @attachment_listener_ids&.delete(session)
    return if !listener_ids || listener_ids.empty?
    session.remove_event_listener(*listener_ids)
  end

  def available_targets
    @available_targets_by_target_id
  end

  def dispose
    @connection.remove_event_listener(*@connection_event_listeners)
    remove_session_listeners(@connection)
  end

  def init
    @connection.send_message('Target.setDiscoverTargets', discover: true)
    @target_ids_for_init.merge(@discovered_targets_by_target_id.keys)
    @initialize_promise.value!
  end

  private def handle_target_created(event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    return if @discovered_targets_by_target_id[target_info.target_id]
    @discovered_targets_by_target_id[target_info.target_id] = target_info

    if target_info.type == 'browser' && target_info.attached
      target = @target_factory.call(target_info, nil)
      @available_targets_by_target_id[target_info.target_id] = target
      finish_initialization_if_ready(target.target_id)
    end

    unless @target_filter_callback.call(target_info)
      @ignored_targets << target_info.target_id
      finish_initialization_if_ready(target_info.target_id)
      return
    end

    target = @target_factory.call(target_info, nil)
    @available_targets_by_target_id[target_info.target_id] = target
    emit_event(TargetManagerEmittedEvents::TargetAvailable, target)
    finish_initialization_if_ready(target.target_id)
  end

  private def handle_target_destroyed(event)
    target_id = event['targetId']
    target_info = @discovered_targets_by_target_id.delete(target_id)
    finish_initialization_if_ready(target_id)

    target = @available_targets_by_target_id.delete(target_id)
    emit_event(TargetManagerEmittedEvents::TargetGone, target)
  end

  class SessionNotCreatedError < StandardError ; end

  private def handle_attached_to_target(parent_session, event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    session_id = event['sessionId']
    session = @connection.session(session_id)
    unless session
      raise SessionNotCreatedError.new("Session #{session_id} was not created.")
    end

    target = @available_targets_by_target_id[target_info.target_id] or raise "Target #{target_info.target_id} is missing"
    setup_attachment_listeners(session)

    @available_targets_by_session_id[session_id] = target

    @target_interceptors[parent_session]&.each do |hook|
      if parent_session.is_a?(Puppeteer::Connection)
        hook.call(target, nil)
      else
        # Sanity check: if parent session is not a connection, it should be
        # present in #attachedTargetsBySessionId.
        available_target = @available_targets_by_session_id[parent_session.id]
        unless available_target
          raise "No target found for the parent session: #{parent_session.id}"
        end
        hook.call(target, available_target)
      end
    end
  end

  private def finish_initialization_if_ready(target_id)
    @target_ids_for_init.delete(target_id)
    if @target_ids_for_init.empty?
      @initialize_promise.fulfill(nil) unless @initialize_promise.resolved?
    end
  end
end
