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
      desc "Default label to drain unmatched patterns"
      config_param :default_route, :string, :default => ""
      desc "Default tag to drain unmatched patterns"
      config_param :default_tag, :string, :default => ""

      config_section :route, param_name: :routes, multi: true do
        desc "New @LABEL if selectors matched"
        config_param :@label, :string, :default => nil
        desc "New tag if selectors matched"
        config_param :tag, :string, :default => ""

        config_section :match, param_name: :selectors, multi: true do
          desc "Label definition to match record. Example: app:nginx. You can specify more values as comma separated list: key1:value1,key2:value2"
          config_param :labels, :hash, :default => {}
          desc "List of namespace definition to filter the record. Ignored if left empty."
          config_param :namespaces, :array, :default => [], value_type: :string
          desc "Negate the selection making it an exclude"
          config_param :negate, :bool, :default => false
        end

      end



      class Route
        def initialize(selectors, tag, router)
          @router = router
          @selectors = selectors
          @tag = tag
        end

        # Evaluate selectors
        # We evaluate <match> statements in order:
        # 1. If match == true and negate == false  -> return true
        # 2. If match == true and negate == true   -> return false
        # 3. If match == false and negate == false -> continue
        # 4. If match == false and negate == true  -> continue
        # There is no match at all                 -> return false
        def match?(labels, namespace)
          @selectors.each do |selector|
            if (filter_select(selector, labels, namespace) and !selector.negate)
              return true
            end
            if (filter_select(selector, labels, namespace) and selector.negate)
              return false
            end
          end
          false
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
          orphan_record = true
          @routers.each do |r|
            if r.match?(input_labels, input_namespace)
              orphan_record = false
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
          if !@default_router.nil? && orphan_record
            if @sticky_tags
              @route_map[tag].push(@default_router)
            end
            if @batch
              event_stream[@default_router].add(time, record)
            else
              @default_router.emit(tag, time, record.dup)
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
        @default_router = nil
        @routes.each do |rule|
          route_router = event_emitter_router(rule['@label'])
          puts rule
          @routers << Route.new(rule.selectors, rule.tag.to_s, route_router)
        end

        if @default_route != '' or @default_tag != ''
          @default_router = Route.new(nil, @default_tag, event_emitter_router(@default_route))
        end

        @access_to_labels = record_accessor_create("$.kubernetes.labels")
        @access_to_namespace = record_accessor_create("$.kubernetes.namespace_name")

        @batch = @emit_mode == :batch
      end
    end
  end
end