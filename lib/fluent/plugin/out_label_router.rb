#
# Copyright 2019- Banzai Cloud
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fluent/plugin/output"
require 'digest/md5'

module Fluent
  module Plugin
    class LabelRouterOutput < BareOutput
      Fluent::Plugin.register_output("label_router", self)

      helpers :event_emitter, :record_accessor

      #record_accessor_create("log")
      #record_accessor_create("$.key1.key2")
      #record_accessor_create("$['key1'][0]['key2']")
      desc "Emit mode. If `batch`, the plugin will emit events per labels matched."
      config_param :emit_mode, :enum, list: [:record, :batch], default: :batch
      desc "Sticky tags will match only one record from an event stream. The same tag will be treated the same way"
      config_param :sticky_tags, :bool, default: true

      config_section :route, param_name: :routes, multi: true do
        desc "New @LABEL if selectors matched"
        config_param :@label, :string, :default => nil
        desc "New tag if selectors matched"
        config_param :tag, :string, :default => ""

        config_section :selector, param_name: :selectors, multi: true do
          desc "Label definition to match record. Example: app:nginx. You can specify more values as comma separated list: key1:value1,key2:value2"
          config_param :labels, :hash, :default => {}
          desc "List of namespace definition to filter the record. Ignored if left empty."
          config_param :namespaces, :array, :default => [], value_type: :string
        end

        config_section :exclude, param_name: :excludes, multi: true do
          desc "Label definition to match record. Example: app:nginx. You can specify more values as comma separated list: key1:value1,key2:value2"
          config_param :labels, :hash, :default => {}
          desc "List of namespace definition to filter the record. Ignored if left empty."
          config_param :namespaces, :array, :default => [], value_type: :string
        end

      end



      class Route
        def initialize(selectors, excludes, tag, router)
          @router = router
          @selectors = selectors
          @excludes = excludes
          @tag = tag
        end

        # Evaluate selectors, excludes
        def match?(labels, namespace)
          @excludes.each do |exclude|
            unless filter_exclude(exclude, labels, namespace)
              return false
            end
          end
          @selectors.each do |selector|
            unless filter_select(selector, labels, namespace)
              return false
            end
          end
          true
        end

        # Returns true if filter passes (no exclude match)
        def filter_exclude(exclude, labels, namespace)
          # Break if list of namespaces is not empty and does not include actual namespace
          unless exclude.namespaces.empty? or !exclude.namespaces.include?(namespace)
            return false
          end
          !match_labels(labels, exclude.labels)
        end

        # Returns true if filter passes (filter match)
        def filter_select(selector, labels, namespace)
          # Break if list of namespaces is not empty and does not include actual namespace
          unless selector.namespaces.empty? or selector.namespaces.include?(namespace)
            return false
          end
          match_labels(labels, selector.labels)
        end

        def emit(tag, time, record)
          if @tag.empty?
            @router.emit(tag, time, record)
          else
            @router.emit(@tag, time, record)
          end
        end

        def emit_es(tag, es)
          if @tag.empty?
            @router.emit_stream(tag, es)
          else
            @router.emit_stream(@tag, es)
          end
        end
        def match_labels(input, match)
          return (match.to_a - input.to_a).empty?
        end
      end

      def process(tag, es)
        if @sticky_tags
          if @route_map.has_key?(tag)
            # We already matched with this tag send events to the routers
            @route_map[tag].each do |r|
              r.emit_es(tag, es.dup)
            end
            return
          end
        end
        event_stream = Hash.new {|h, k| h[k] = Fluent::MultiEventStream.new }
        es.each do |time, record|
          input_labels = @access_to_labels.call(record).to_h
          input_namespace = @access_to_namespace.call(record).to_s
          @routers.each do |r|
            if r.match?(input_labels, input_namespace)
              if @sticky_tags
                @route_map[tag].push(r)
              end
              if @batch
                event_stream[r].add(time, record)
              else
                r.emit(tag, time, record.dup)
              end
            end
          end
          if @batch
            event_stream.each do |r, es|
              r.emit_es(tag, es.dup)
            end
          end
        end
      end

      def configure(conf)
        super
        @route_map = Hash.new { |h, k| h[k] = Array.new }
        @routers = []
        @routes.each do |rule|
          route_router = event_emitter_router(rule['@label'])
          @routers << Route.new(rule.selectors, rule.excludes, rule.tag.to_s, route_router)
        end

        @access_to_labels = record_accessor_create("$.kubernetes.labels")
        @access_to_namespace = record_accessor_create("$.kubernetes.namespace_name")

        @batch = @emit_mode == :batch
      end
    end
  end
end