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

  sub_test_case 'test_routing' do
    test 'basic configuration' do
      routing_conf = %[
<route>
  <match>
    labels app:app1
  </match>
  <match>
    labels app2:app2
    negate true
  </match>
  tag new_app_tag
</route>
<route>
  <match>
    labels app:app1
    namespaces default,test
  </match>
  <match>
    labels app:app2
    namespaces system
    negate true
  </match>
  tag new_app_tag
</route>
<route>
  <match>
    labels app:nginx
    namespaces dev,sandbox
  </match>
</route>
]
      d = Fluent::Test::Driver::BaseOwner.new(Fluent::Plugin::LabelRouterOutput)
      d.configure(routing_conf)

      r1 = Fluent::Plugin::LabelRouterOutput::Route.new(d.instance.routes[0].selectors, "",nil)
      # Match selector
      assert_equal(true, r1.match?({"app" => "app1"},""))
      # Exclude via label
      assert_equal(false, r1.match?({"app2" => "app2"},""))
      # Not presented value in exclude
      assert_equal(true, r1.match?({"app3" => "app2"},""))

      r2 = Fluent::Plugin::LabelRouterOutput::Route.new(d.instance.routes[1].selectors, "",nil)
      # Match selector and namespace
      assert_equal(true, r2.match?({"app" => "app1"},"test"))
      # Exclude via namespace
      assert_equal(false, r2.match?({"app" => "app2"},"system"))
      # Excluded namespace but not matching labels
      assert_equal(true, r2.match?({"app3" => "app"},"system"))

      r3 = Fluent::Plugin::LabelRouterOutput::Route.new(d.instance.routes[2].selectors, "",nil)
      assert_equal(true, r2.match?({"app" => "nginx"},"dev"))
      assert_equal(true, r2.match?({"app" => "nginx"},"sandbox"))
    end
  end

  sub_test_case 'test_tag' do
    test 'normal' do
      CONFIG = %[
<route>
  <match>
    labels app:app1
  </match>
  tag new_app_tag
</route>
]
      event_time = event_time("2019-07-17 11:11:11 UTC")
      d = create_driver(CONFIG)
      d.run(default_tag: 'test') do
        d.feed(event_time, {"kubernetes" => {"labels" => {"app" => "app1"} } } )
      end
      d.run(default_tag: 'test2') do
        d.feed(event_time, {"kubernetes" => {"labels" => {"app" => "app2"} } } )
      end
      events = d.events

      assert_equal(1, events.size)
      assert_equal ["new_app_tag", event_time, {"kubernetes" => {"labels" => {"app" => "app1"} } }], events[0]
    end
  end
end
