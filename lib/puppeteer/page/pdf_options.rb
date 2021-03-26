require 'mime/types'

class Puppeteer::Page
  # /**
  # * @typedef {Object} PDFOptions
  # * @property {number=} scale
  # * @property {boolean=} displayHeaderFooter
  # * @property {string=} headerTemplate
  # * @property {string=} footerTemplate
  # * @property {boolean=} printBackground
  # * @property {boolean=} landscape
  # * @property {string=} pageRanges
  # * @property {string=} format
  # * @property {string|number=} width
  # * @property {string|number=} height
  # * @property {boolean=} preferCSSPageSize
  # * @property {!{top?: string|number, bottom?: string|number, left?: string|number, right?: string|number}=} margin
  # * @property {string=} path
  # */
  class PDFOptions
    # @params options [Hash]
    def initialize(options)
      unless options[:path]
        # Original puppeteer allows path = nil, however nothing to do without path actually.
        # Also in most case, users forget to specify path parameter. So let's raise ArgumentError.
        raise ArgumentError('"path" parameter must be specified.')
      end

      @scale = options[:scale]
      @display_header_footer = options[:display_header_footer]
      @header_template = options[:header_template]
      @footer_template = options[:footer_template]
      @print_background = options[:print_background]
      @landscape = options[:landscape]
      @page_ranges = options[:page_ranges]
      @format = options[:format]
      @width = options[:width]
      @height = options[:height]
      @prefer_css_page_size = options[:prefer_css_page_size]
      @margin = Margin.new(options[:margin] || {})
      @path = options[:path]
    end

    attr_reader :path

    class PaperSize
      def initialize(width:, height:)
        @width = width
        @height = height
      end
      attr_reader :width, :height
    end

    PAPER_FORMATS = {
      'letter' => PaperSize.new(width: 8.5, height: 11),
      'legal' => PaperSize.new(width: 8.5, height: 14),
      'tabloid' => PaperSize.new(width: 11, height: 17),
      'ledger' => PaperSize.new(width: 17, height: 11),
      'a0' => PaperSize.new(width: 33.1, height: 46.8),
      'a1' => PaperSize.new(width: 23.4, height: 33.1),
      'a2' => PaperSize.new(width: 16.54, height: 23.4),
      'a3' => PaperSize.new(width: 11.7, height: 16.54),
      'a4' => PaperSize.new(width: 8.27, height: 11.7),
      'a5' => PaperSize.new(width: 5.83, height: 8.27),
      'a6' => PaperSize.new(width: 4.13, height: 5.83),
    }

    UNIT_TO_PIXELS = {
      'px' => 1,
      'in' => 96,
      'cm' => 37.8,
      'mm' => 3.78,
    }

    # @param parameter [String|Integer|nil]
    private def convert_print_parameter_to_inches(parameter)
      return nil if parameter.nil?

      pixels =
        if parameter.is_a?(Numeric)
          parameter.to_i
        elsif parameter.is_a?(String)
          unit = parameter[-2..-1].downcase
          value =
            if UNIT_TO_PIXELS.has_key?(unit)
              parameter[0...-2].to_i
            else
              unit = 'px'
              parameter.to_i
            end

          value * UNIT_TO_PIXELS[unit]
        else
          raise ArgumentError.new("page.pdf() Cannot handle parameter type: #{parameter.class}")
        end

      pixels / 96
    end

    private def paper_size
      @paper_size ||= calc_paper_size
    end

    # @return [PaperSize]
    private def calc_paper_size
      if @format
        PAPER_FORMATS[@format.downcase] or raise ArgumentError.new("Unknown paper format: #{@format}")
      else
        PaperSize.new(
          width: convert_print_parameter_to_inches(@width) || 8.5,
          height: convert_print_parameter_to_inches(@height) || 11.0,
        )
      end
    end

    class Margin
      def initialize(options)
        @top = options[:top]
        @bottom = options[:bottom]
        @left = options[:left]
        @right = options[:right]
      end

      def translate(&block)
        new_margin ={
          top: block.call(@top),
          bottom: block.call(@bottom),
          left: block.call(@left),
          right: block.call(@right),
        }
        Margin.new(new_margin)
      end
      attr_reader :top, :bottom, :left, :right
    end

    private def margin
      @__margin ||= calc_margin
    end

    private def calc_margin
      @margin.translate do |value|
        convert_print_parameter_to_inches(value) || 0
      end
    end

    def page_print_args
      {
        transferMode: 'ReturnAsStream',
        landscape: @landscape || false,
        displayHeaderFooter: @display_header_footer || false,
        headerTemplate: @header_template || '',
        footerTemplate: @footer_template || '',
        printBackground: @print_background || false,
        scale: @scale || 1,
        paperWidth: paper_size.width,
        paperHeight: paper_size.height,
        marginTop: margin.top,
        marginBottom: margin.bottom,
        marginLeft: margin.left,
        marginRight: margin.right,
        pageRanges: @page_ranges || '',
        preferCSSPageSize: @prefer_css_page_size || false,
      }
    end
  end
end
