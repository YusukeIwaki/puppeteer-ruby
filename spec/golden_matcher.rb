require 'chunky_png'
require 'rspec/expectations'

module GoldenMatcher
  extend RSpec::Matchers::DSL
  include ChunkyPNG::Color

  matcher :be_golden do |file_path|
    expected_image = ChunkyPNG::Image.from_file("spec/integration/golden-chromium/#{file_path}")
    match do |blob|
      actual_image = ChunkyPNG::Image.from_blob(blob)

      actual_image.width == expected_image.width && actual_image.height == expected_image.height && actual_image.pixels == expected_image.pixels
    end
    failure_message do |blob|
      actual_image = ChunkyPNG::Image.from_blob(blob)

      if actual_image.width != expected_image.width || actual_image.height != expected_image.height
        "image size unmatch. actual: [#{actual_image.width}, #{actual_image.height}]  expected: [#{expected_image.width}, #{expected_image.height}]"
      else
        diffimage = ChunkyPNG::Image.new(expected_image.width, expected_image.height, WHITE)

        diff = []

        expected_image.height.times do |y|
          expected_image.row(y).each_with_index do |pixel, x|
            unless pixel == actual_image[x, y]
              score = Math.sqrt(
                (r(actual_image[x, y]) - r(pixel)) ** 2 +
                (g(actual_image[x, y]) - g(pixel)) ** 2 +
                (b(actual_image[x, y]) - b(pixel)) ** 2,
              ) / Math.sqrt(MAX ** 2 * 3)

              diffimage[x, y] = grayscale(MAX - (score * 255).round)
              diff << score
            end
          end
        end

        texts = []
        texts << 'image pixel unmatch.'
        texts << "pixels (total): #{expected_image.pixels.length},"
        texts << "pixels changed: #{diff.length},"
        diffsum = diff.inject { |sum, value| sum + value }
        texts << "image changed (%): #{100 * diffsum / expected_image.pixels.length}%"

        diffimage.save("diff-#{file_path}.png")
        texts.join(" ")
      end
    end
  end
end
