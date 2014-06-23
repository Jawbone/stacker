require 'active_support/core_ext/string/inflections'
require 'json'
require 'memoist'
require 'stacker/differ'
require 'stacker/stack/component'
require 'stacker/dsl'

module Stacker
  class Stack
    class Template < Component

      FORMAT_VERSION = '2010-09-09'

      extend Memoist

      def exists?
        File.exists? path
      end

      def local
        @local ||= begin
          if exists?
            if path.end_with? '.rb'
                template = ruby_template path
            else
                template = JSON.parse File.read path
            end
            template['AWSTemplateFormatVersion'] ||= FORMAT_VERSION
            template
          else
            {}
          end
        end
      end

      def remote
        @remote ||= JSON.parse client.template
      rescue AWS::CloudFormation::Errors::ValidationError => err
        if err.message =~ /does not exist/
          raise DoesNotExistError.new err.message
        else
          raise Error.new err.message
        end
      end

      def diff *args
        Differ.json_diff local, remote, *args
      end
      memoize :diff

      def write value = local
        File.write path, JSONFormatter.format(value)
      end

      def dump
        write remote
      end

      private
      def ruby_template template_path
          context = self.stack.options.fetch 'template_context', {}
          dsl_template = Stacker::DSL.file_to_template template_path, context
          JSON.parse dsl_template.to_json
      end
      def path
        if @path.nil?
            [File.join(stack.region.templates_path,
                "#{stack.options.fetch('template_name', stack.name)}.json"),
            File.join(stack.region.templates_path,
                "#{stack.options.fetch('template_name', stack.name)}.rb")].each { |f|
                @path = f if File.exists?(f)
            }
        end
        @path
      end

      class JSONFormatter
        STR = '\"[^\"]+\"'

        def self.format object
          formatted = JSON.pretty_generate object

          # put empty arrays on a single line
          formatted.gsub! /: \[\s*\]/m, ': []'

          # put { "Ref": ... } on a single line
          formatted.gsub! /\{\s+\"Ref\"\:\s+(?<ref>#{STR})\s+\}/m,
            '{ "Ref": \\k<ref> }'

          # put { "Fn::GetAtt": ... } on a single line
          formatted.gsub! /\{\s+\"Fn::GetAtt\"\: \[\s+(?<key>#{STR}),\s+(?<val>#{STR})\s+\]\s+\}/m,
            '{ "Fn::GetAtt": [ \\k<key>, \\k<val> ] }'

          formatted + "\n"
        end
      end

    end
  end
end
