module Rouge
  module Lexers
    class Sed < RegexLexer
      desc 'sed, the ultimate stream editor'

      tag 'sed'
      filenames '*.sed'
      mimetypes 'text/x-sed'

      def self.analyze_text(text)
        return 1 if text.shebang? 'sed'
      end

      class Regex < RegexLexer
        state :root do
          rule /\\./, 'Literal.String.Escape'
          rule /\[/, 'Punctuation', :brackets
          rule /[$^.*]/, 'Operator'
          rule /[()]/, 'Punctuation'
          rule /./, 'Literal.String.Regex'
        end

        state :brackets do
          rule /\^?/ do
            token 'Punctuation'
            pop!; push :brackets_int
          end
        end

        state :brackets_int do
          # ranges
          rule /.-./, 'Name.Variable'
          rule /\]/, 'Punctuation', :pop!
          rule /./, 'Literal.String.Regex'
        end
      end

      class Replacement < RegexLexer
        state :root do
          rule /\\./m, 'Literal.String.Escape'
          rule /&/, 'Operator'
          rule /[^\\&]+/m, 'Text'
        end
      end

      def regex
        @regex ||= Regex.new(options)
      end

      def replacement
        @replacement ||= Replacement.new(options)
      end

      start { regex.reset!; replacement.reset! }

      state :whitespace do
        rule /\s+/m, 'Text'
        rule(/#.*?\n/) { token 'Comment'; reset_stack }
        rule(/\n/) { token 'Text'; reset_stack }
        rule(/;/) { token 'Punctuation'; reset_stack }
      end

      state :root do
        mixin :addr_range
      end

      edot = /\\.|./m

      state :command do
        mixin :whitespace

        # subst and transliteration
        rule /(s)(.)(#{edot}*?)(\2)(#{edot}*?)(\2)/m do |m|
          token 'Keyword', m[1]
          token 'Punctuation', m[2]
          delegate regex, m[3]
          token 'Punctuation', m[4]
          delegate replacement, m[5]
          token 'Punctuation', m[6]


          pop!; push :flags
        end

        rule /(y)(.)(#{edot}*?)(\2)(#{edot}*?)(\2)/m do |m|
          token 'Keyword', m[1]
          token 'Punctuation', m[2]
          delegate replacement, m[3]
          token 'Punctuation', m[4]
          delegate replacement, m[5]
          token 'Punctuation', m[6]

          pop!
        end

        # commands that take a text segment as an argument
        rule /([aic])(\s*)/ do
          group 'Keyword'; group 'Text'; pop!; push :text
        end

        rule /[pd]/, 'Keyword'

        # commands that take a number argument
        rule /([qQl])(\s+)(\d+)/i do
          group 'Keyword'; group 'Text'; group 'Literal.Number'
          pop!
        end

        # no-argument commands
        rule /[={}dDgGhHlnpPqx]/, 'Keyword', :pop!

        # commands that take a filename argument
        rule /([rRwW])(\s+)(\S+)/ do
          group 'Keyword'; group 'Text'; group 'Name'
          pop!
        end

        # commands that take a label argument
        rule /([:btT])(\s+)(\S+)/ do
          group 'Keyword'; group 'Text'; group 'Name.Label'
          pop!
        end
      end

      state :addr_range do
        mixin :whitespace

        ### address ranges ###
        addr_tok = 'Keyword.Namespace'
        rule /\d+/, addr_tok
        rule /[$,~+!]/, addr_tok

        rule %r((/)(\\.|.)*?(/)) do |m|
          token addr_tok, m[1]; delegate regex, m[2]; token addr_tok, m[3]
        end

        # alternate regex rage delimiters
        rule %r((\\)(.)(\\.|.)*?(\2)) do |m|
          token addr_tok, m[1] + m[2]
          delegate regex, m[3]
          token addr_tok, m[4]
        end

        rule(//) { push :command }
      end

      state :text do
        rule /[^\\\n]+/, 'Literal.String'
        rule /\\\n/, 'Literal.String.Escape'
        rule /\\/, 'Literal.String'
        rule /\n/, 'Text', :pop!
      end

      state :flags do
        rule /[gp]+/, 'Keyword', :pop!

        # writing to a file with the subst command.
        # who'da thunk...?
        rule /([wW])(\s+)(\S+)/ do
          token 'Keyword'; token 'Text'; token 'Name'
        end

        rule(//) { pop! }
      end
    end
  end
end