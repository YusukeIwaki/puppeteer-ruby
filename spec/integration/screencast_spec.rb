require 'spec_helper'
require 'tmpdir'

RSpec.describe 'Screencasts' do
  describe 'Page.screencast' do
    it 'should work' do
      Dir.mktmpdir('puppeteer-screencast-') do |directory|
        with_test_state do |page:, **|
          path = File.join(directory, 'recording.webm')
          recorder = page.screencast(
            path: path,
            scale: 0.5,
            crop: { width: 100, height: 100, x: 0, y: 0 },
            speed: 0.5,
          )

          page.goto('data:text/html,<input>')
          input = page.locator('input').wait_handle
          input.type_text('ab', delay: 100)
          input.dispose
          recorder.stop

          expect(File.size(path)).to be > 0
        end
      end
    end

    it 'should work concurrently' do
      Dir.mktmpdir('puppeteer-screencast-') do |directory|
        with_test_state do |page:, **|
          path1 = File.join(directory, 'recording-1.webm')
          path2 = File.join(directory, 'recording-2.webm')
          recorder = page.screencast(path: path1)
          recorder2 = page.screencast(path: path2)

          page.goto('data:text/html,<input>')
          input = page.locator('input').wait_handle
          input.type_text('ab', delay: 100)
          recorder.stop
          input.type_text('ab', delay: 100)
          recorder2.stop
          input.dispose

          ratio = File.size(path2).fdiv(File.size(path1))
          delta = 1.3
          expect(ratio).to be > 2 - delta
          expect(ratio).to be < 2 + delta
        end
      end
    end

    it 'should validate options' do
      with_test_state do |page:, **|
        expect { page.screencast(scale: 0) }.to raise_error(ArgumentError)
        expect { page.screencast(scale: -1) }.to raise_error(ArgumentError)
        expect { page.screencast(speed: 0) }.to raise_error(ArgumentError)
        expect { page.screencast(speed: -1) }.to raise_error(ArgumentError)
        expect do
          page.screencast(crop: { x: 0, y: 0, height: 1, width: 0 })
        end.to raise_error(ArgumentError)
        expect do
          page.screencast(crop: { x: 0, y: 0, height: 0, width: 1 })
        end.to raise_error(ArgumentError)
        expect do
          page.screencast(crop: { x: -1, y: 0, height: 1, width: 1 })
        end.to raise_error(ArgumentError)
        expect do
          page.screencast(crop: { x: 0, y: -1, height: 1, width: 1 })
        end.to raise_error(ArgumentError)
        expect do
          page.screencast(crop: { x: 0, y: 0, height: 10_000, width: 1 })
        end.to raise_error(ArgumentError)
        expect do
          page.screencast(crop: { x: 0, y: 0, height: 1, width: 10_000 })
        end.to raise_error(ArgumentError)
        expect do
          page.screencast(ffmpeg_path: 'non-existent-path')
        end.to raise_error(Errno::ENOENT)
      end
    end
  end
end
