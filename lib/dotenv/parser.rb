require "dotenv/substitutions/variable"
require "dotenv/substitutions/command" if RUBY_VERSION > "1.8.7"

require "strscan"

module Dotenv
  class FormatError < SyntaxError; end

  # This class enables parsing of a string for key value pairs to be returned
  # and stored in the Environment. It allows for variable substitutions and
  # exporting of variables.
  #
  # file = lines?
  # lines = line more_lines?
  # more_lines = newline line more_lines?
  # line = whitespace? statement? whitespace? comment? whitespace?
  # statement = export_statement | assignment_statement
  # export_statement = 'export' whitespace+ assignment
  # assignment_statement = assignment
  # assignment = key '=' value
  # key = [A-Za-z_][A-Za-z0-9_]+
  # value = double_quoted_value | single_quoted_value | unquoted_value
  # double_quoted_value = '"' ( '\' anything | expansion | !'"' )+ '"'
  # single_quoted_value = ''' ( '\' anything | !''' )+ '''
  # unquoted_value = ('\' anything | expansion | !whitespace)+
  # expansion = param_expansion | command_expansion
  # param_expansion = bare_param_expansion | curly_param_expansion
  # bare_param_expansion = '$' key
  # curly_param_expansion = '${' key '}'
  # command_expansion = '$(' command ')'
  # command = <balanced parens>
  # comment = '#' [^\r\n]+
  # whitespace = (' ' | '\t')+
  # newline = '\r'? '\n'
  #
  class Parser
    @substitutions = [
      Dotenv::Substitutions::Variable,
      Dotenv::Substitutions::Command,
    ]

    class << self
      attr_reader :substitutions

      def call(string, _=nil)
        new(string).call
      end
    end

    def initialize(string)
      @string = string
    end

    def call
      state = :source
      scanner = StringScanner.new(@string)
      env = {}
      while true
        p state => scanner
        case state
        when :source
          state = :line
        when :line
          scanner.skip(/[ \t]*/)
          if scanner.eos?
            return env
          elsif scanner.match? /\r?\n/
            state = :newline
          elsif scanner.match? /#/
            state = :comment
          else
            state = :statement
          end
        when :statement
          if scanner.match?(/export\s/)
            state = :export_statement
          elsif scanner.match?(/\S/)
            state = :assignment_statement
          elsif scanner.eos?
            return env
          else
            raise "Expected statement"
          end
        when :comment_statement
          state = :comment
        when :export_statement
          scanner.skip(/export\b/) or raise "Expected 'export'"
          scanner.skip(/[ \t]+/) or raise "Expected whitespace"
          state = :assignment
        when :assignment_statement
          state = :assignment
        when :assignment
          key = scanner.scan(/[A-Za-z_][A-Za-z0-9_]*/) or raise "Expected key"
          scanner.skip(/[ \t]*/)
          scanner.skip(/=/) or raise "Expected '='"
          scanner.skip(/[ \t]*/)
          if scanner.match?(/"/)
            state = :assignment_double_quoted_value
          elsif scanner.match?(/'/)
            state = :assignment_single_quoted_value
          else
            state = :assignment_value
          end
        when :assignment_value
          value = scanner.scan(/\S+/) || ""
          scanner.skip(/[ \t]*/)
          env[key] = value
          state = :assignment_end
        when :assignment_double_quoted_value
          scanner.skip(/"/) or raise "Expected '\"'"
          value = ""
          state = :assignment_double_quoted_value_contents
        when :assignment_double_quoted_value_contents
          if scanner.scan(/[^"\\]+/)
            value << scanner[0]
          elsif scanner.scan(/\\(.)/)
            value << scanner[1]
          elsif scanner.skip(/"/)
            scanner.skip(/[ \t]*/)
            env[key] = value
            state = :assignment_end
          else
            raise "Expected double quoted string contents"
          end
        when :assignment_single_quoted_value
          scanner.skip(/'/) or raise "Expected \"'\""
          value = ""
          state = :assignment_single_quoted_value_contents
        when :assignment_single_quoted_value_contents
          if scanner.scan(/[^'\\]+/)
            value << scanner[0]
          elsif scanner.scan(/\\(.)/)
            value << scanner[1]
          elsif scanner.skip(/'/)
            scanner.skip(/[ \t]*/)
            env[key] = value
            state = :assignment_end
          else
            raise "Expected single quoted string contents"
          end
        when :assignment_end
          if scanner.match?(/#/)
            state = :comment
          else
            state = :newline
          end
        when :comment
          scanner.skip(/#.*/)
          state = :newline
        when :newline
          if scanner.eos?
            return env
          elsif scanner.skip(/\r?\n/)
            state = :statement
          else
            raise "Expected newline"
          end
        else
          raise "Unknown state: #{state}"
        end
      end
    end
  end
end
