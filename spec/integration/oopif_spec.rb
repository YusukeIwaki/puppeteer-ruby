require 'spec_helper'

metadata = {
  skip: Puppeteer.env.firefox?,
  enable_site_per_process_flag: true,
  browser_context: :incognito,
  sinatra: true,
}

RSpec.describe 'OOPIF', **metadata do
  include Utils::AttachFrame
  include Utils::DetachFrame
  include Utils::NavigateFrame

  def oopifs(context)
    context.targets.select do |target|
      target.raw_type == 'iframe'
    end
  end

  it 'should treat OOP iframes and normal iframes the same' do
    page.goto(server_empty_page)

    predicate = ->(frame) { frame.url&.end_with?('/empty.html') }
    page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
      attach_frame(page, 'frame2', "#{server_cross_process_prefix}/empty.html")
    end
    expect(page.main_frame.child_frames.size).to eq(2)
  end

  it 'should track navigations within OOP iframes' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', "#{server_cross_process_prefix}/empty.html")
    end
    expect(frame.url).to end_with('/empty.html')

    navigate_frame(page, 'frame1', "#{server_cross_process_prefix}/frames/frame.html")
    expect(frame.url).to end_with('/frames/frame.html')
  end

  it 'should support OOP iframes becoming normal iframes again' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
    end

    expect(frame).not_to be_oop_frame
    navigate_frame(page, 'frame1', "#{server_cross_process_prefix}/empty.html")
    expect(frame).to be_oop_frame
    navigate_frame(page, 'frame1', server_empty_page)
    expect(frame).not_to be_oop_frame

    expect(page.frames.size).to eq(2)
  end

  it 'should support frames within OOP frames' do
    page.goto(server_empty_page)
    frame1_promise = page.async_wait_for_frame(predicate: -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 })
    frame2_promise = page.async_wait_for_frame(predicate: -> (frame) { page.frames.index { |_frame| _frame == frame } == 2 })

    attach_frame(page, 'frame1', "#{server_cross_process_prefix}/frames/one-frame.html")
    frame1, frame2 = await_all(frame1_promise, frame2_promise)
    expect(frame1.url).to end_with('/one-frame.html')
    expect(frame2.url).to end_with('/frames/frame.html')
  end

  it 'should support OOP iframes getting detached' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
      navigate_frame(page, 'frame1', "#{server_cross_process_prefix}/empty.html")
    end
    expect(frame).to be_oop_frame
    detach_frame(page, 'frame1')
    expect(page.frames.size).to eq(1)
  end

  it 'should support wait for navigation for transitions from local to OOPIF' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
    end
    expect(frame).not_to be_oop_frame

    frame.wait_for_navigation do
      navigate_frame(page, 'frame1', "#{server_cross_process_prefix}/empty.html")
    end
    expect(frame).to be_oop_frame
    detach_frame(page, 'frame1')
    expect(page.frames.count).to eq(1)
  end

  it 'should keep track of a frames OOP state' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
    end

    expect(frame.url).to include('/empty.html')
    navigate_frame(page, 'frame1', server_empty_page)
    expect(frame.url).to eq(server_empty_page)
  end

  it 'should support evaluating in oop iframes' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
    end
    frame.evaluate("() => { _test = 'Test 123'; }")
    result = frame.evaluate('() => window._test')
    expect(result).to eq('Test 123')
  end

  it 'should provide access to elements' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', server_empty_page)
    end
    frame.evaluate(<<~JAVASCRIPT)
    () => {
      const button = document.createElement('button');
      button.id = 'test-button';
      document.body.appendChild(button);
    }
    JAVASCRIPT
    frame.click('#test-button')
  end

  it 'should report oopif frames' do
    predicate = -> (frame) { frame.url&.end_with?('/oopif.html') }
    frame = page.wait_for_frame(predicate: predicate) do
      page.goto("#{server_prefix}/dynamic-oopif.html")
    end
    expect(frame).to be_oop_frame
    expect(oopifs(browser_context).size).to eq(1)
    expect(page.frames.size).to eq(2)
  end

  it 'should wait for inner OOPIFs' do
    predicate = -> (frame) { frame.url&.end_with?('/inner-frame2.html') }
    frame2 = page.wait_for_frame(predicate: predicate) do
      page.goto("http://mainframe:#{server_port}/main-frame.html")
    end
    expect(oopifs(browser_context).size).to eq(2)
    expect(page.frames.count { |frame| frame.oop_frame? }).to eq(2)
    expect(frame2.evaluate('() => document.querySelectorAll("button").length')).to eq(1)
  end

  it 'should load oopif iframes with subresources and request interception' do
    predicate = -> (frame) { frame.url&.end_with?('/oopif.html') }
    frame_promise = page.async_wait_for_frame(predicate: predicate)
    page.request_interception = true
    page.on('request') { |req| req.continue }
    page.goto("#{server_prefix}/dynamic-oopif.html")
    await frame_promise
    expect(oopifs(browser_context).size).to eq(1)
  end

  it 'should support frames within OOP iframes' do
    predicate = -> (frame) { frame.url&.end_with?('/oopif.html') }
    oop_iframe = page.wait_for_frame(predicate: predicate) do
      page.goto("#{server_prefix}/dynamic-oopif.html")
    end
    attach_frame(oop_iframe, 'frame1', "#{server_cross_process_prefix}/empty.html")

    frame1 = oop_iframe.child_frames.first
    expect(frame1.url).to end_with('/empty.html')
    navigate_frame(oop_iframe, 'frame1', "#{server_cross_process_prefix}/oopif.html")
    expect(frame1.url).to end_with('/oopif.html')
    detach_frame(oop_iframe, 'frame1')
    expect(oop_iframe.child_frames).to be_empty
  end

  it 'clickablePoint, boundingBox, boxModel should work for elements inside OOPIFs' do
    page.goto(server_empty_page)
    predicate = -> (frame) { page.frames.index { |_frame| _frame == frame } == 1 }
    frame = page.wait_for_frame(predicate: predicate) do
      attach_frame(page, 'frame1', "#{server_cross_process_prefix}/empty.html")
    end

    page.evaluate(<<~JAVASCRIPT)
    () => {
      document.body.style.border = '50px solid black';
      document.body.style.margin = '50px';
      document.body.style.padding = '50px';
    }
    JAVASCRIPT
    frame.evaluate(<<~JAVASCRIPT)
    () => {
      const button = document.createElement('button');
      button.id = 'test-button';
      button.innerText = 'click';
      document.body.appendChild(button);
    }
    JAVASCRIPT

    button = frame.wait_for_selector('#test-button', visible: true)

    result = button.clickable_point
    expect(result.x).to be > 150 # padding + margin + border left
    expect(result.y).to be > 150 # padding + margin + border top

    result_box_model = button.box_model
    %i(content border margin padding).each do |attr_name|
      result_box_model.send(attr_name).each do |part|
        expect(part.x).to be > 150 # padding + margin + border left
        expect(part.y).to be > 150 # padding + margin + border top
      end
    end

    result_bounding_box = button.bounding_box
    expect(result_bounding_box.x).to be > 150 # padding + margin + border left
    expect(result_bounding_box.y).to be > 150 # padding + margin + border top
  end

  it 'should resolve immediately if the frame already exists' do
    page.goto(server_empty_page)
    attach_frame(page, 'frame2', "#{server_cross_process_prefix}/empty.html")
    predicate = ->(frame) { frame.url&.end_with?('/empty.html') }
    frame = page.wait_for_frame(predicate: predicate)
    expect(frame.url).to end_with("/empty.html")
  end
end
