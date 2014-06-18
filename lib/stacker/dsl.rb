require 'json'
require 'set'
module Stacker
    module DSL
        def self.jsonify_name name
            name.to_s.gsub(/([a-z]{1})([A-Z]{1})/, '\1_\2').gsub('_', ' ').split.map {|w| w.capitalize }.join('')
        end
        CLOUDFORMATION_VERSION = "2010-09-09"
        class TemplatePart
            def initialize template, name, &block
                @name = name
                @template = template
                @hash_map = {}
                instance_eval &block unless block.nil?
            end

            def self.json_field name, &block
                define_method name do |arg=nil|
                    json_fields << name.to_sym
                    block.call(arg)
                end
            end

            def to_hash
                res = {}
                json_fields.each do |k|
                    res[to_json_name(k)] = to_json_value(k, send(k))
                end
                @hash_map.each do |k, v|
                    if respond_to?(k)
                        res[to_json_name(k)] = to_json_value(k, send(k))
                    elsif @hash_map.has_key?(k)
                        res[to_json_name(k)] = to_json_value(k, @hash_map[k])
                    end
                end
                res
            end

            def method_missing method_name, *args, &block
                if block.nil?
                    @hash_map[method_name] = args.length == 1 ? args[0] : args
                else
                    @hash_map[method_name] = TemplatePart.new(@template, to_json_name(method_name), &block)
                end
            end

            def ref name
                {"Ref" => name.kind_of?(Symbol) ? to_json_name(name) : name }
            end

            def base64 value
                {"Fn::Base64" => value }
            end

            def findInMap map, top_key, second_key
                {"Fn::FindInMap" => [map, top_key, second_key] }
            end
            def getatt resource, attribute
                {"Fn::GetAtt" => [resource, attribute] }
            end
            def getazs region
                {"Fn::GetAZs" => region }
            end
            def join delimiter, *args
                {"Fn::Join" => [delimiter, args] }
            end
            def select idx, list
                {"Fn::Select" => [idx, list] }
            end
            def account_id
                ref('AWS::AccountId')
            end
            def notification_arns
                ref('AWS::NotificationARNs')
            end
            def no_value
                ref('AWS::NoValue')
            end
            def region
                ref('AWS::Region')
            end
            def stack_id
                ref('AWS::StackId')
            end
            def stack_name
                ref('AWS::StackName')
            end
            private
            def json_fields
                @json_fields ||= Set.new
            end
            def to_json_name name
                if respond_to?("#{name}_json_name".to_sym)
                    send "#{name}_json_name".to_sym
                else
                    ::Stacker::DSL.jsonify_name(name)
                end
            end
            def to_json_value key, value
                if respond_to?("#{key}_json_value".to_sym)
                    send "#{key}_json_value".to_sym, value
                elsif value.respond_to?(:to_hash)
                    value.to_hash
                else
                    value
                end
            end
        end

        class Mapping
            attr_accessor :name
            attr_reader :values

            def initialize name, &block
                @name = name
                @values = {}
                instance_eval &block unless block.nil?
            end

            def method_missing method, *args, &block
                @values[method.to_s] = args[0]
            end
        end

        class Parameter < TemplatePart

            json_field :type do |arg=nil|
                unless arg.nil?
                    raise "Invalid parameter type" unless arg == :string || arg == :number
                    @type = arg
                end
                @type
            end
            json_field :max_length do |arg=nil|
                unless arg.nil?
                    raise "max_length is only valid for strings" unless @type == :string
                    @max_length = arg
                end
                @max_length
            end
            json_field :min_length do |arg=nil|
                unless arg.nil?
                    raise "min_length is only valid for strings" unless @type == :string
                    @min_length = arg
                end
                @min_length
            end

            json_field :max_value do |arg=nil|
                unless arg.nil?
                    raise "max_value is only valid for numbers." unless @type == :number
                    @max_value = arg
                end
                @max_value
            end

            json_field :min_value do |arg=nil|
                unless arg.nil?
                    raise "min_value is only valid for numbers" unless @type == :number
                    @min_value = arg
                end
                @min_value
            end

            def type_json_value val
                val.to_s.capitalize
            end
        end
        class Resource < TemplatePart
            json_field :depends_on do |arg=nil|
                unless arg.nil?
                    @depends_on = ::Stacker::DSL.jsonify_name(arg)
                end
                @depends_on
            end
        end

        class Output < TemplatePart
        end

        class Template
            attr_accessor :description, :version, :name

            def initialize name, description = nil, &block
                @name = name
                @description = description
                @mappings = {}
                @outputs = {}
                @resources = {}
                @parameters = {}
                @version = nil
                instance_eval &block unless block.nil?
            end
            def description desc
                @description = desc
            end
            def parameter name, &block
                raise "Parameter name already used" if @parameters.has_key?(name.to_s.capitalize)
                @parameters[name.to_s.capitalize] = Parameter.new(self, name, &block)
            end
            def mapping map_name, data
                map_key = map_name.to_s.capitalize
                raise "Mapping name already exists!" if @mappings.has_key?(map_key)
                @mappings[map_key] = data
            end
            def resource name, &block
                key = name.to_s.capitalize
                raise "Resource name already exists!" if @resources.has_key?(key)
                @resources[key] = Resource.new(self, name, &block)
            end
            def output name, &block
                key = name.to_s.capitalize
                raise "Output already exists with that name!" if @outputs.has_key?(key)
                @outputs[key] = Output.new(self, name, &block)
            end
            def for_json what
                h = {}
                what.each do |name,val|
                    h[::Stacker::DSL.jsonify_name name] = val.to_hash
                end
                h
            end
            def to_json
                JSON.pretty_generate({
                    "AWSTemplateFormatVersion" => @version || CLOUDFORMATION_VERSION,
                    "Description" => @description || "Some stack.",
                    "Parameters" => for_json(@parameters) || {},
                    "Mappings" => for_json(@mappings) || {},
                    "Resources" => for_json(@resources) || {},
                    "Outputs" => for_json(@outputs) || {},
                })
            end
            private

        end

        def self.template name, description = nil, &block
            Template.new(name, description, &block)
        end
    end
end
