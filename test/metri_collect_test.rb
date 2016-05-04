require 'test_helper'

class MetriCollectTest < Minitest::Test
  class User
    class << self
      def count; 0 end
      def active_count; 0 end
    end
  end

  class System
    class << self
      def load_average; 0 end
      def used_memory; 0 end
      def free_memory; 0 end
    end
  end

  class Application
    class << self
      def errors; 0 end
    end
  end

  def setup
    @publisher = MetriCollect::Publisher[:test]
    @watcher   = MetriCollect::Watcher[:test]

    MetriCollect.configure do |config|
      config.application("CareerArc") do |application|
        application.publishers :test
        application.watchers :test

        application.metrics do
          namespace "Application" do
            namespace "Users" do
              metric "Total" do
                value User.count
              end

              metric "Active" do
                value User.active_count
              end
            end
          end

          namespace "Unicorn" do
            metric "WorkerCount" do
              value rand(1..10)
            end

            group "Requests" do
              sock_path = "/home/deploy/www/career_arc/shared/system/.sock"
              stats = { sock_path => OpenStruct.new(active: rand(1..10), queued: rand(1..10)) }

              metric do
                value stats[sock_path].active
                dimensions "Type" => "Active"
              end

              metric do
                value stats[sock_path].queued
                dimensions "Type" => "Queued"
              end
            end
          end
        end
      end

      config.application("CareerBeam") do |application|
        application.publishers :test

        application.metrics do
          namespace "System" do
            metric "LoadAverage" do
              value System.load_average
            end

            namespace "Memory" do
              metric "Used" do
                value System.used_memory, unit: :megabytes
              end

              metric "Free" do
                name "FreeMemory"
                namespace "CareerBeam/System/FreeMemory"
                value System.free_memory, unit: :megabytes
                dimensions "Type" => "Free", "SystemId" => "Workstation-1"
                timestamp Time.now
              end
            end
          end
        end
      end

      config.application("Namespace") do |application|
        application.publishers :test
        application.prefix_metrics_with "development"

        application.metrics do
          namespace "System" do
            metric "LoadAverage" do
              value System.load_average
            end
          end
        end
      end

      config.template :instance do |name, &block|
        dimensions "InstanceId" => "i-123456"
      end

      config.application("Template") do |application|
        application.publishers :test

        application.metrics do
          metric "Instance" do
            template :instance
            value 25
            dimensions "Type" => "Specific"
          end

          group "InstanceGroup" do
            metric do
              template :instance
              value 10
              dimensions "Type" => "Group"
            end
          end
        end
      end

      config.application("Watchers") do |application|
        application.watchers :test

        application.metrics do
          metric "Errors" do
            value Application.errors
            watch do
              name "Error Rate Too High"
              description "Triggered when the Application error rate is too high"
              condition { sum.over_period(3600) > 10 }
            end
          end
        end
      end
    end

    @careerarc   = MetriCollect["CareerArc"]
    @careerbeam  = MetriCollect["CareerBeam"]
    @namespace   = MetriCollect["Namespace"]
    @template    = MetriCollect["Template"]
    @watchers    = MetriCollect["Watchers"]
  end

  def test_metrics
    User.stub :count, 50 do
      User.stub :active_count, 25 do
        total, active, workers, active_requests, queued_requests = @careerarc.metrics.to_a

        assert_equal 50, total.value
        assert_equal "Total", total.name
        assert_equal "CareerArc/Application/Users", total.namespace
        assert_equal :count, total.unit

        assert_equal 25, active.value
        assert_equal "Active", active.name
        assert_equal "CareerArc/Application/Users", active.namespace
        assert_equal :count, active.unit

        assert_equal "Requests", active_requests.name
        assert_equal "CareerArc/Unicorn", active_requests.namespace
        assert_equal "Type", active_requests.dimensions.first[:name]
        assert_equal "Active", active_requests.dimensions.first[:value]

        assert_equal "Requests", queued_requests.name
        assert_equal "CareerArc/Unicorn", queued_requests.namespace
        assert_equal "Type", queued_requests.dimensions.first[:name]
        assert_equal "Queued", queued_requests.dimensions.first[:value]

        refute_nil active_requests.timestamp
        refute_nil queued_requests.timestamp

        assert_equal active_requests.timestamp.to_i, queued_requests.timestamp.to_i
      end
    end

    System.stub :load_average, 0.75 do
      System.stub :used_memory, 3000 do
        System.stub :free_memory, 2000 do
          Time.stub :now, Time.at(0) do
            load_average, used, free = @careerbeam.metrics.to_a

            assert_equal 0.75, load_average.value
            assert_equal "LoadAverage", load_average.name
            assert_equal "CareerBeam/System", load_average.namespace
            assert_equal :count, load_average.unit

            assert_equal 3000, used.value
            assert_equal "Used", used.name
            assert_equal "CareerBeam/System/Memory", used.namespace
            assert_equal :megabytes, used.unit

            assert_equal 2000, free.value
            assert_equal "FreeMemory", free.name
            assert_equal "CareerBeam/System/FreeMemory", free.namespace
            assert_equal :megabytes, free.unit
            assert_equal Time.at(0), free.timestamp
            assert_equal [{ name: "Type", value: "Free" }, { name: "SystemId", value: "Workstation-1" }], free.dimensions
          end
        end
      end
    end

    System.stub :load_average, 0.25 do
      load_average, _ = @namespace.metrics.to_a

      assert_equal 0.25, load_average.value
      assert_equal "LoadAverage", load_average.name
      assert_equal "Namespace/development/System", load_average.namespace
      assert_equal :count, load_average.unit
    end

    instance, instance_group, _ = @template.metrics.to_a

    assert_equal "Instance", instance.name
    assert_equal "Template", instance.namespace
    assert_equal 25, instance.value
    assert_equal "Type", instance.dimensions.first[:name]
    assert_equal "Specific", instance.dimensions.first[:value]
    assert_equal "InstanceId", instance.dimensions.last[:name]
    assert_equal "i-123456", instance.dimensions.last[:value]

    assert_equal "InstanceGroup", instance_group.name
    assert_equal "Template", instance_group.namespace
    assert_equal 10, instance_group.value
    assert_equal "Type", instance_group.dimensions.first[:name]
    assert_equal "Group", instance_group.dimensions.first[:value]
    assert_equal "InstanceId", instance_group.dimensions.last[:name]
    assert_equal "i-123456", instance_group.dimensions.last[:value]
  end

  def test_publish
    User.stub :count, 10 do
      User.stub :active_count, 5 do
        total, active = @careerarc.metrics.to_a

        @careerarc.publish(total)

        assert @publisher.published?(total)
        refute @publisher.published?(active)

        @publisher.clear

        @careerarc.publish_all

        assert @publisher.published?(total)
        assert @publisher.published?(active)
      end
    end
  end

  def test_direct_publish
    timestamp = Time.now
    options   = {
      namespace: "CareerArc/Counters",
      name: "aae:heartbeat",
      value: 1,
      timestamp: timestamp,
      unit: :count
    }

    MetriCollect["Namespace"].publish(options)

    metric = @publisher.published.last

    assert_equal "CareerArc/development/Counters", metric.namespace
    assert_equal "aae:heartbeat", metric.name
    assert_equal 1, metric.value
    assert_equal timestamp, metric.timestamp
    assert_equal :count, metric.unit

    options.merge!(template: :instance)

    MetriCollect["CareerArc"].publish(options)

    metric = @publisher.published.last

    assert_equal "CareerArc/Counters", metric.namespace
    assert_equal "aae:heartbeat", metric.name
    assert_equal 1, metric.value
    assert_equal timestamp, metric.timestamp
    assert_equal :count, metric.unit
    assert_equal "InstanceId", metric.dimensions.first[:name]
    assert_equal "i-123456", metric.dimensions.first[:value]

    MetriCollect["CareerArc"].publish do
      name "Direct Block Count"
      namespace "CareerArc/Counters"
      value 10, unit: :count
      timestamp timestamp
    end

    metric = @publisher.published.last

    assert_equal "CareerArc/Counters", metric.namespace
    assert_equal "Direct Block Count", metric.name
    assert_equal 10, metric.value
    assert_equal timestamp, metric.timestamp
    assert_equal :count, metric.unit
  end

  def test_watchers
    Application.stub :errors, 1 do
      errors = @watchers.metrics.to_a[0]
      watch = errors.watches[0]
      now = Time.now.to_i

      if now % 3600 >= 3598
        puts "Sleeping 5 seconds to make sure we don't cross a time boundary..."
        sleep 5
      end

      results = 10.times.map do
        @watcher.watch(errors)
        @watcher.status(watch.name)
      end

      assert_equal 0, results.count {|r| r != :ok}

      @watcher.watch(errors)

      assert_equal :triggered, @watcher.status(watch.name)
    end
  end

  def test_direct_watchers
    timestamp = Time.now
    watch_name = "Queued Distributions Alarm"
    options   = {
      namespace: "CareerArc/Counters",
      name: "ade:dispatcher:distribution:queued",
      value: 1,
      timestamp: timestamp,
      unit: :count,
      watches: [{
        name: watch_name,
        description: "Triggered when there are too many queued distributions",
        evaluations: 1,
        statistic: :sum,
        period: 3600,
        comparison: :>,
        threshold: 10
      }]
    }

    if timestamp.to_i % 3600 >= 3598
      puts "Sleeping 5 seconds to make sure we don't cross a time boundary..."
      sleep 5
    end

    results = 10.times.map do
      @watchers.publish(options)
      @watcher.status(watch_name)
    end

    assert_equal 0, results.count {|r| r != :ok}

    @watchers.publish(options)

    assert_equal :triggered, @watcher.status(watch_name)
  end

  def test_cloud_watch_publisher_grouping
    metric    = { name: "Metric" }
    publisher = MetriCollect::Publisher::CloudWatchPublisher.new(region: "us-east")
    group     = publisher.send(:array_to_groups, [metric], 20)

    assert_equal group, [[metric]]
  end

  def test_runner
    runner = MetriCollect::Runner.new("CareerArc", frequency: 5, iterations: 3)
    runner.start
  end
end
