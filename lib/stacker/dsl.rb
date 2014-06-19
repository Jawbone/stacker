require 'json'
require 'set'

module Stacker
    module DSL
        # I have no idea what i'm doing or why I'm doing it, but I'm doing the shit out of it
        module TemplatePart
            module ClassMethods
                def element name, opts = {}
                    var_name = "@#{name.to_s}".to_sym

                    define_method name.to_sym do |arg=nil|
                        instance_variable_set var_name, arg unless arg.nil?
                        instance_variable_get var_name
                    end
                    begin
                        elements = self.send :class_variable_get, :@@elements
                    rescue
                        elements = {}
                    end
                    elements[name] = opts
                    self.send :class_variable_set, :@@elements, elements
                    self.send :class_variable_get, :@@elements
                end
                def elements
                    self.send :class_variable_get, :@@elements
                end
            end
            def self.included base
                base.extend ClassMethods
            end

            def initialize template, name, opts={}, &block
                @template = template
                @name = name
                opts.each do |k,v|
                    send k, v
                end
                instance_eval &block
            end

            attr_reader :template, :name

            def to_hash
                hash = {}
                self.class.elements.each do |k,v|
                    val = self.send k.to_sym
                    if v.has_key? :transform
                        val = v[:transform].call val
                    end
                    hash[k] = val unless val.nil?
                end
                hash
            end
        end

        module TemplateFunctions
            def ref target
                {"Ref" => target}
            end

            def stack_id
                ref 'AWS::StackId'
            end
            def base64 value
                {'Fn::Base64' => value }
            end
            def findInMap map, top, second
                {'Fn::FindInMap' => [map, top, second]}
            end
            def getaz region=nil
                region = self.region if region.nil?
                {'Fn::GetAZs' => region }
            end
            def getatt resource, attribute
                {'Fn::GetAtt' => [resource, attribute] }
            end
            def join delimiter, *args
                {'Fn::Join' => [delimiter, args] }
            end
            def select idx, list
                {'Fn::Select' => [idx, list] }
            end
            def account_id
                ref 'AWS::AccountId'
            end
            def notification_arns
                ref 'AWS::NotificationARNS'
            end
            def no_value
                ref 'AWS::NoValue'
            end
            def region
                ref 'AWS::Region'
            end
            def stack_name
                ref 'AWS::StackName'
            end
        end

        class Parameter
            include TemplatePart
            include TemplateFunctions

            element :Type
            element :Description
            element :AllowedPattern
            element :MaxLength
            element :MaxValue
            element :MinLength
            element :MinValue
            element :Default

            def Type arg=nil
                @Type = arg.downcase unless arg.nil?
                raise "Invalid parameter type #{@Type}" unless @Type == :string or @Type == :number
                @Type.to_s.capitalize
            end

            alias_method :type, :Type
        end
        class Resource
            include TemplatePart
            include TemplateFunctions
            class Properties
                include TemplateFunctions

                def method_missing method_name, *args, &block
                    properties[method_name] = args.length == 1 ? args[0] : args
                end

                def properties
                    @properties ||= {}
                end
            end

            element :Type
            element :Properties, :transform => Proc.new { |arg| arg.properties }
            element :DependsOn

            def Properties &block
                @properties ||= Properties.new
                @properties.instance_eval &block unless block.nil?
                @properties
            end

            def output name, opts = {}, &block
                my_name = self.name
                output = template.output name do
                    if opts.has_key? :att
                        Value getatt(self.name, opts[:att])
                    else
                        Value ref(my_name)
                    end
                    Description opts[:description] if opts.has_key? :description
                end
                output.instance_eval &block unless block.nil?
            end

            alias_method :properties, :Properties
            alias_method :type, :Type
        end

        class Output
            include TemplatePart
            include TemplateFunctions

            element :Description
            element :Value
            element :Condition

        end
        class Template
            CLOUDFORMATION_VERSION = '2010-09-09'
            attr_accessor :description, :version, :name

            def initialize name, description = nil, &block
                @name = name
                @description = description
                @version = nil
                instance_eval &block unless block.nil?
            end
            def description desc
                @description = desc
            end
            def parameter name, opts = {}, &block
                raise "Parameter #{name} already exists" if parameters.has_key? name
                parameters[name] = Parameter.new self, name, opts, &block
            end
            def mapping map_name, data
                raise "Mapping #{name} already exists" if mappings.has_key? map_name
                mappings[map_name] = data
            end
            def resource name, opts = {}, &block
                raise "Resource #{name} already exists" if resources.has_key? name
                resources[name] = Resource.new self, name, opts, &block
            end
            def output name, opts = {}, &block
                raise "Output #{name} already exists" if outputs.has_key? name
                outputs[name] = Output.new self, name, opts, &block
            end
            def for_json what
                h = {}
                what.each do |name,val|
                    h[name] = val.to_hash
                end
                h
            end
            def to_hash
                {
                    "AWSTemplateFormatVersion" => @version || CLOUDFORMATION_VERSION,
                    "Description" => @description || "Some stack.",
                    "Parameters" => for_json(parameters) || {},
                    "Mappings" => for_json(mappings) || {},
                    "Resources" => for_json(resources) || {},
                    "Outputs" => for_json(outputs) || {},
                }
            end
            def to_json
                JSON.pretty_generate(to_hash)
            end
            private
            def mappings
                @mappings ||= {}
            end
            def resources
                @resources ||= {}
            end
            def parameters
                @parameters ||= {}
            end
            def outputs
                @outputs ||= {}
            end
        end

        def self.template name, description = nil, &block
            Template.new(name, description, &block)
        end
        def self.file_to_template file
            t = Template.new(File.basename file)
            t.instance_eval File.read(file), file
            t
        end
    end
end
