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

require "helper"
require "fluent/plugin/out_label_router.rb"

class LabelRouterOutputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  private

  def create_driver(conf)
    d = Fluent::Test::Driver::BaseOwner.new(Fluent::Plugin::LabelRouterOutput)
    d.extend(Fluent::Test::Driver::EventFeeder)
    Fluent::Engine.root_agent.define_singleton_method(:find_label) do |label_name|
      obj = Object.new
      obj.define_singleton_method(:event_router){ d.instance.router } # for test...
      obj
    end
    d.configure(conf)
  end

  sub_test_case 'test_tag' do
    test 'normal' do
      CONFIG = %[
<route>
  labels app:app1
  tag new_app_tag
</route>
]
      event_time = event_time("2019-07-17 11:11:11 UTC")
      d = create_driver(CONFIG)
      d.run(default_tag: 'test') do
        d.feed(event_time, {"kubernetes" => {"labels" => {"app" => "app1"} } } )
        d.feed(event_time, {"kubernetes" => {"labels" => {"app" => "app2"} } } )
      end
      events = d.events

      assert_equal(1, events.size)
      assert_equal ["new_app_tag", event_time, {"kubernetes" => {"labels" => {"app" => "app1"} } }], events[0]
    end
  end
end
