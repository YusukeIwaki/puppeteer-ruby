require 'spec_helper'

RSpec.describe 'Touchscreen' do
  def all_events(page)
    page.evaluate('() => allEvents')
  end

  describe 'Touchscreen#tap' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        page.tap(selector: 'button')
        expect(all_events(page)).to eq([
          {
            'type' => 'pointerdown',
            'x' => 5,
            'y' => 5,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 5, 'clientY' => 5, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 5, 'clientY' => 5, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerup',
            'x' => 5,
            'y' => 5,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchend',
            'changedTouches' => [
              { 'clientX' => 5, 'clientY' => 5, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [],
          },
          {
            'type' => 'click',
            'x' => 5,
            'y' => 5,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
        ])
      end
    end

    it 'should work if another touch is already active' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        page.touchscreen.touch_start(100, 100)
        page.tap(selector: 'button')

        expect(all_events(page)).to eq([
          {
            'type' => 'pointerdown',
            'x' => 100,
            'y' => 100,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 100, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 100, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerdown',
            'x' => 5,
            'y' => 5,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 5, 'clientY' => 5, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 100, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 5, 'clientY' => 5, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerup',
            'x' => 5,
            'y' => 5,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchend',
            'changedTouches' => [
              { 'clientX' => 5, 'clientY' => 5, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 100, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
        ])
      end
    end
  end

  describe 'Touchscreen#touch_move' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        # Note that touchmoves are sometimes not triggered if consecutive
        # touchmoves are less than 15 pixels.
        #
        # See https://github.com/puppeteer/puppeteer/issues/10836
        page.touchscreen.touch_start(0, 0)
        page.touchscreen.touch_move(15, 15)
        page.touchscreen.touch_move(30.5, 30)
        page.touchscreen.touch_move(50, 45.4)
        page.touchscreen.touch_move(80, 50)
        page.touchscreen.touch_end

        expect(all_events(page)).to eq([
          {
            'type' => 'pointerdown',
            'x' => 0,
            'y' => 0,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 0, 'clientY' => 0, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 0, 'clientY' => 0, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 15,
            'y' => 15,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 15, 'clientY' => 15, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 15, 'clientY' => 15, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 31,
            'y' => 30,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 31, 'clientY' => 30, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 31, 'clientY' => 30, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 50,
            'y' => 45,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 45, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 45, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 80,
            'y' => 50,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 80, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 80, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerup',
            'x' => 80,
            'y' => 50,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchend',
            'changedTouches' => [
              { 'clientX' => 80, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [],
          },
        ])
      end
    end

    it 'should work with two touches' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        page.touchscreen.touch_start(0, 0)
        page.touchscreen.touch_start(30, 10)
        page.touchscreen.touch_move(15, 15)

        expect(all_events(page)).to eq([
          {
            'type' => 'pointerdown',
            'x' => 0,
            'y' => 0,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 0, 'clientY' => 0, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 0, 'clientY' => 0, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerdown',
            'x' => 30,
            'y' => 10,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 30, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 0, 'clientY' => 0, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 30, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 15,
            'y' => 15,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 15, 'clientY' => 15, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 15, 'clientY' => 15, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 30, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
        ])
      end
    end

    it 'should work when moving touches separately' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        touch1 = page.touchscreen.touch_start(20, 20)
        touch1.move(50, 10)
        touch2 = page.touchscreen.touch_start(20, 50)
        touch2.move(50, 50)
        touch2.end
        touch1.end

        expect(all_events(page)).to eq([
          {
            'type' => 'pointerdown',
            'x' => 20,
            'y' => 20,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 50,
            'y' => 10,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerdown',
            'x' => 20,
            'y' => 50,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 20, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 20, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 50,
            'y' => 50,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 50, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerup',
            'x' => 50,
            'y' => 50,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchend',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerup',
            'x' => 50,
            'y' => 10,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchend',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 10, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [],
          },
        ])
      end
    end

    it 'should work with three touches' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        touch1 = page.touchscreen.touch_start(50, 50)
        touch1.move(50, 100)
        page.touchscreen.touch_start(20, 20)
        touch1.end
        touch3 = page.touchscreen.touch_start(20, 100)
        touch3.move(60, 100)

        expect(all_events(page)).to eq([
          {
            'type' => 'pointerdown',
            'x' => 50,
            'y' => 50,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 50, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 50,
            'y' => 100,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerdown',
            'x' => 20,
            'y' => 20,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 50, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerup',
            'x' => 50,
            'y' => 100,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => Math::PI / 2,
            'azimuthAngle' => 0,
            'pressure' => 0,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchend',
            'changedTouches' => [
              { 'clientX' => 50, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointerdown',
            'x' => 20,
            'y' => 100,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchstart',
            'changedTouches' => [
              { 'clientX' => 20, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 20, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
          {
            'type' => 'pointermove',
            'x' => 60,
            'y' => 100,
            'width' => 1,
            'height' => 1,
            'altitudeAngle' => 1.5707963267948966,
            'azimuthAngle' => 0,
            'pressure' => 0.5,
            'pointerType' => 'touch',
            'twist' => 0,
            'tiltX' => 0,
            'tiltY' => 0,
          },
          {
            'type' => 'touchmove',
            'changedTouches' => [
              { 'clientX' => 60, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
            'activeTouches' => [
              { 'clientX' => 20, 'clientY' => 20, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
              { 'clientX' => 60, 'clientY' => 100, 'radiusX' => 0.5, 'radiusY' => 0.5, 'force' => 0.5 },
            ],
          },
        ])
      end
    end

    it 'should throw if no touch was started' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        expect { page.touchscreen.touch_move(15, 15) }.to raise_error(Puppeteer::TouchError, 'Must start a new Touch first')
      end
    end
  end

  describe 'Touchscreen#touch_end' do
    it 'should throw when ending touch through Touchscreeen that was already ended' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/touchscreen.html")

        touch = page.touchscreen.touch_start(100, 100)
        touch.move(50, 100)
        touch.end
        expect { page.touchscreen.touch_end }.to raise_error(Puppeteer::TouchError, 'Must start a new Touch first')
      end
    end
  end
end
