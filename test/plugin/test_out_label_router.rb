require "helper"
require "fluent/plugin/out_label_router.rb"

class LabelSelectorOutputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  test "failure" do
    flunk
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::LabelSelectorOutput).configure(conf)
  end
end
