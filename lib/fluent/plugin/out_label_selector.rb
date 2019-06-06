#
# Copyright 2019- tarokkk
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

module Fluent
  module Plugin
    class LabelSelectorOutput < Fluent::Plugin::Output
      Fluent::Plugin.register_output("label_selector", self)

      helpers :event_emitter, :record_accessor

      #record_accessor_create("log")
      #record_accessor_create("$.key1.key2")
      #record_accessor_create("$['key1'][0]['key2']")

      config_section :select, param_name: :selectors, multi: true do
        desc "This will be the new tag if selectors matched"
        config_param :tag, :string
        desc "JSON style list of labels"
        config_param :labels, :hash
        desc "If not empty namespaces will be filtered as well"
        config_param :namespace, :string, :default => ""
      end

      def process(tag, es)
        new_tag = tag
        es.each do |time, record|
          input_labels = @access_to_labels.call(record).to_h
          input_namespace = @access_to_namespace.call(record).to_s
          @select_rules.each do |rule_tag, source_labels, namespace|
            if namespace.empty? or input_namespace == namespace
              puts "ns in record " + namespace
              if !input_labels.empty? and match_labels(input_labels, source_labels)
                new_tag = rule_tag
              end
            end
          end
          router.emit(new_tag, time, record)
        end
      end

      def match_labels(input, match)
        return (match.to_a - input.to_a).empty?
      end

      def configure(conf)
        super

        @select_rules = []
        @access_to_labels = record_accessor_create("$.kubernetes.labels")
        @access_to_namespace = record_accessor_create("$.kubernetes.namespace_name")
        @selectors.each do |rule|
          @select_rules.push([rule.tag.to_s, rule.labels.to_h, rule.namespace.to_s])
        end
      end
    end
  end
end