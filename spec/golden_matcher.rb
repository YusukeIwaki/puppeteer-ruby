require 'chunky_png'
require 'rspec/expectations'

module GoldenMatcher
  extend RSpec::Matchers::DSL
  include ChunkyPNG::Color

  PIXEL_MATCH_THRESHOLD = 0.1

  matcher :be_golden do |file_path|
    expected_image = ChunkyPNG::Image.from_file("spec/integration/golden-chromium/#{file_path}")
    match do |blob|
      @actual_image = ChunkyPNG::Image.from_blob(blob)
      @size_mismatch = @actual_image.width != expected_image.width || @actual_image.height != expected_image.height
      return false if @size_mismatch

      @diff_image = ChunkyPNG::Image.new(expected_image.width, expected_image.height, WHITE)
      @diff_scores = []

      expected_image.height.times do |y|
        expected_image.row(y).each_with_index do |pixel, x|
          actual_pixel = @actual_image[x, y]
          next if pixel == actual_pixel

          score = Math.sqrt(
            (r(actual_pixel) - r(pixel)) ** 2 +
            (g(actual_pixel) - g(pixel)) ** 2 +
            (b(actual_pixel) - b(pixel)) ** 2,
          ) / Math.sqrt(MAX ** 2 * 3)

          next if score <= PIXEL_MATCH_THRESHOLD

          @diff_image[x, y] = grayscale(MAX - (score * 255).round)
          @diff_scores << score
        end
      end

      @diff_scores.empty?
    end
    failure_message do |blob|
      actual_image = @actual_image || ChunkyPNG::Image.from_blob(blob)

      if @size_mismatch
        return "image size unmatch. actual: [#{actual_image.width}, #{actual_image.height}]  expected: [#{expected_image.width}, #{expected_image.height}]"
      end

      diff_scores = @diff_scores || []
      diff_image = @diff_image

      texts = []
      texts << 'image pixel unmatch.'
      texts << "pixels (total): #{expected_image.pixels.length},"
      texts << "pixels changed: #{diff_scores.length},"
      diffsum = diff_scores.inject(0.0) { |sum, value| sum + value }
      texts << "image changed (%): #{100 * diffsum / expected_image.pixels.length}%"
      texts << "threshold: #{PIXEL_MATCH_THRESHOLD}"

      diff_image&.save("diff-#{file_path}.png")
      texts.join(' ')
    end
  end

  def match_golden(file_path)
    be_golden(file_path)
  end
end
