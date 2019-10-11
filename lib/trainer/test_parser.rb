module Trainer
  class TestParser
    attr_accessor :data

    attr_accessor :file_content

    attr_accessor :raw_json

    attr_accessor :test_summaries
    attr_accessor :actions_invocation_record

    # Returns a hash with the path being the key, and the value
    # defining if the tests were successful
    def self.auto_convert(config)
      FastlaneCore::PrintTable.print_values(config: config,
                                             title: "Summary for trainer #{Trainer::VERSION}")

      containing_dir = config[:path]
      # Xcode < 10
      files = Dir["#{containing_dir}/**/Logs/Test/*TestSummaries.plist"]
      files += Dir["#{containing_dir}/Test/*TestSummaries.plist"]
      files += Dir["#{containing_dir}/*TestSummaries.plist"]
      # Xcode 10
      files += Dir["#{containing_dir}/**/Logs/Test/*.xcresult/TestSummaries.plist"]
      files += Dir["#{containing_dir}/Test/*.xcresult/TestSummaries.plist"]
      files += Dir["#{containing_dir}/*.xcresult/TestSummaries.plist"]
      files += Dir[containing_dir] if containing_dir.end_with?(".plist") # if it's the exact path to a plist file
      # Xcode 11
      files += Dir["#{containing_dir}/**/Logs/Test/*.xcresult"]
      files += Dir["#{containing_dir}/Test/*.xcresult"]
      files += Dir["#{containing_dir}/*.xcresult"]
      files << containing_dir if File.extname(containing_dir) == ".xcresult"

      if files.empty?
        UI.user_error!("No test result files found in directory '#{containing_dir}', make sure the file name ends with 'TestSummaries.plist' or '.xcresult'")
      end

      return_hash = {}
      files.each do |path|
        if config[:output_directory]
          FileUtils.mkdir_p(config[:output_directory])
          # Remove .xcresult or .plist extension
          if path.end_with?(".xcresult")
            filename = File.basename(path).gsub(".xcresult", config[:extension])
          else
            filename = File.basename(path).gsub(".plist", config[:extension])
          end
          to_path = File.join(config[:output_directory], filename)
        else
          # Remove .xcresult or .plist extension
          if path.end_with?(".xcresult")
            to_path = path.gsub(".xcresult", config[:extension])
          else
            to_path = path.gsub(".plist", config[:extension])
          end
        end

        tp = Trainer::TestParser.new(path, config)
        File.write(to_path, tp.to_junit)
        puts "Successfully generated '#{to_path}'"

        return_hash[to_path] = tp.return_hash
      end
      return_hash
    end

    def initialize(path, config = {})
      path = File.expand_path(path)
      UI.user_error!("File not found at path '#{path}'") unless File.exist?(path)

      if File.directory?(path) && path.end_with?(".xcresult")
        parse_xcresult(path)

        if config[:output_directory]
          to_path = config[:output_directory]
        else
          to_path = File.dirname(path)
        end

        if config[:output_videos]
          export_videos(path, to_path)
        end

        if config[:output_logs]
          export_logs(path, to_path, config[:log_regex], config[:log_name])
        end
      else
        self.file_content = File.read(path)
        self.raw_json = Plist.parse_xml(self.file_content)

        return if self.raw_json["FormatVersion"].to_s.length.zero? # maybe that's a useless plist file

        ensure_file_valid!
        parse_content(config[:xcpretty_naming])
      end
    end

    # Returns the JUnit report as String
    def to_junit
      JunitGenerator.new(self.data).generate
    end

    # @return [Bool] were all tests successful? Is false if at least one test failed
    def tests_successful?
      self.data.collect { |a| a[:number_of_failures] }.all?(&:zero?)
    end

    def return_hash
      output = {}
      output[:test_count] = self.data.map{ |a| a[:number_of_tests] }.inject(:+)
      output[:failing_test_count] = self.data.map{ |a| a[:number_of_failures] }.inject(:+)
      output[:passing_test_count] = output[:test_count] - output[:failing_test_count]

      output[:failing_tests] = self.data.map { |a|
        a[:tests] 
      }.flatten.select { |a| 
        a[:status] != "Success"
      }.map { |a| 
        { :identifier => a[:identifier].sub('.', '/').delete('()') } 
      }

      output[:passing_tests] = self.data.map { |a|
        a[:tests] 
      }.flatten.select { |a| 
        a[:status] == "Success"
      }.map { |a| 
        { :identifier => a[:identifier].sub('.', '/').delete('()') } 
      }

      output
    end

    private

    def ensure_file_valid!
      format_version = self.raw_json["FormatVersion"]
      supported_versions = ["1.1", "1.2"]
      UI.user_error!("Format version '#{format_version}' is not supported, must be #{supported_versions.join(', ')}") unless supported_versions.include?(format_version)
    end

    # Converts the raw plist test structure into something that's easier to enumerate
    def unfold_tests(data)
      # `data` looks like this
      # => [{"Subtests"=>
      #  [{"Subtests"=>
      #     [{"Subtests"=>
      #        [{"Duration"=>0.4,
      #          "TestIdentifier"=>"Unit/testExample()",
      #          "TestName"=>"testExample()",
      #          "TestObjectClass"=>"IDESchemeActionTestSummary",
      #          "TestStatus"=>"Success",
      #          "TestSummaryGUID"=>"4A24BFED-03E6-4FBE-BC5E-2D80023C06B4"},
      #         {"FailureSummaries"=>
      #           [{"FileName"=>"/Users/krausefx/Developer/themoji/Unit/Unit.swift",
      #             "LineNumber"=>34,
      #             "Message"=>"XCTAssertTrue failed - ",
      #             "PerformanceFailure"=>false}],
      #          "TestIdentifier"=>"Unit/testExample2()",

      tests = []
      data.each do |current_hash|
        if current_hash["Subtests"]
          tests += unfold_tests(current_hash["Subtests"])
        end
        if current_hash["TestStatus"]
          tests << current_hash
        end
      end
      return tests
    end

    # Returns the test group and test name from the passed summary and test
    # Pass xcpretty_naming = true to get the test naming aligned with xcpretty
    def test_group_and_name(testable_summary, test, xcpretty_naming)
      if xcpretty_naming
        group = testable_summary["TargetName"] + "." + test["TestIdentifier"].split("/")[0..-2].join(".")
        name = test["TestName"][0..-3]
      else
        group = test["TestIdentifier"].split("/")[0..-2].join(".")
        name = test["TestName"]
      end
      return group, name
    end

    def execute_cmd(cmd)
      output = `#{cmd}`
      raise "Failed to execute - #{cmd}" unless $?.success?
      return output
    end

    def parse_xcresult(path)
      require 'shellwords'
      path = Shellwords.escape(path)

      # Executes xcresulttool to get JSON format of the result bundle object
      result_bundle_object_raw = execute_cmd("xcrun xcresulttool get --format json --path #{path}")
      result_bundle_object = JSON.parse(result_bundle_object_raw)

      # Parses JSON into ActionsInvocationRecord to find a list of all ids for ActionTestPlanRunSummaries
      self.actions_invocation_record = Trainer::XCResult::ActionsInvocationRecord.new(result_bundle_object)
      test_refs = self.actions_invocation_record.actions.map do |action|
        action.action_result.tests_ref
      end.compact
      ids = test_refs.map(&:id)

      # Maps ids into ActionTestPlanRunSummaries by executing xcresulttool to get JSON
      # containing specific information for each test summary,
      summaries = ids.map do |id|
        raw = execute_cmd("xcrun xcresulttool get --format json --path #{path} --id #{id}")
        json = JSON.parse(raw)
        Trainer::XCResult::ActionTestPlanRunSummaries.new(json)
      end

      # Converts the ActionTestPlanRunSummaries to data for junit generator
      failures = actions_invocation_record.issues.test_failure_summaries || []

      # Gets flat list of all ActionTestableSummary
      all_summaries = summaries.map(&:summaries).flatten
      self.test_summaries = all_summaries.map(&:testable_summaries).flatten

      summaries_to_data(self.test_summaries, failures)
    end

    def summaries_to_data(summaries, failures)

      # Maps ActionTestableSummary to rows for junit generator
      rows = summaries.map do |testable_summary|
        all_tests = testable_summary.all_tests.flatten

        test_rows = all_tests.map do |test|
          test_row = {
            identifier: "#{test.parent.name}.#{test.name}",
            name: test.name,
            duration: test.duration,
            status: test.test_status,
            test_group: test.parent.name,

            # These don't map to anything but keeping empty strings
            guid: ""
          }

          # Set failure message if failure found
          failure = test.find_failure(failures)
          if failure
            test_row[:failures] = [{
              file_name: "",
              line_number: 0,
              message: "",
              performance_failure: {},
              failure_message: failure.failure_message
            }]
          end

          test_row
        end

        row = {
          project_path: testable_summary.project_relative_path,
          target_name: testable_summary.target_name,
          test_name: testable_summary.name,
          duration: all_tests.map(&:duration).inject(:+),
          tests: test_rows
        }

        row[:number_of_tests] = row[:tests].count
        row[:number_of_failures] = row[:tests].find_all { |a| (a[:failures] || []).count > 0 }.count

        row
      end

      self.data = rows
    end

    def export_logs(path, output_base_path, log_regex = nil, filename)
      log_refs = self.actions_invocation_record.actions.map do |action| 
        action.action_result.log_ref 
      end.flatten

      ids = log_refs.map(&:id)

      logs = ids.map do |id|
        raw = execute_cmd("xcrun xcresulttool get --format json --path #{path} --id #{id}")
        json = JSON.parse(raw)
        Trainer::XCResult::ActivityLogSection.create(json)
      end

      all_test_logs = logs.map(&:all_test_logs).flatten
      all_test_logs.each do |log|
        lines = log.emitted_output.split("\n")

        if !log_regex.nil?
          lines = lines.select do |line| 
            /#{log_regex}/ === line
          end
        end

        test_name = "#{log.suite_name}-#{log.test_name}".delete('()')

        output_path = "#{output_base_path}/#{log.result == "succeeded" ? "passing" : "failing"}/#{test_name}"
        FileUtils.mkdir_p output_path

        puts "Writing logs for #{test_name}..."
        File.write("#{output_path}/#{filename.nil? ? "output.log" : filename}", lines.join("\n"))
      end
    end

    def export_videos(path, output_base_path)
      all_tests = self.test_summaries.map(&:all_tests).flatten

      all_tests.each do |test|
        test_name = "#{test.identifier.sub('/', '-').delete('()')}"

        # Load the metadata for this test
        id = test.summary_ref.id
        raw = execute_cmd("xcrun xcresulttool get --format json --path #{path} --id #{id}")
        json = JSON.parse(raw)
        test_summary = Trainer::XCResult::ActionTestSummary.new(json, test)
        all_attachments = test_summary.activity_summaries.map(&:all_attachments).flatten

        Dir.mktmpdir do |dir|       
          # Write all the attachments out to disk   
          all_attachments.each do |attachment|
            execute_cmd("xcrun xcresulttool export --path #{path} --output-path '#{dir}/#{attachment.filename}' --id #{attachment.payload_ref.id} --type file")
          end
          
          ordered_names = all_attachments.map do |attachment| 
            "#{dir}/#{attachment.filename}" 
          end

          output_path = "#{output_base_path}/#{test.test_status == "Success" ? "passing" : "failing"}/#{test_name}"
          FileUtils.mkdir_p output_path

          # Create a video from those attachments
          puts "Generating video for #{test_name} from #{ordered_names.count} images..."
          execute_cmd("cat #{ordered_names.join(' ')} | ffmpeg -hide_banner -loglevel panic -framerate 3 -f image2pipe  -i - #{output_path}/output.mp4")
        end
      end
    end

    # Convert the Hashes and Arrays in something more useful
    def parse_content(xcpretty_naming)
      self.data = self.raw_json["TestableSummaries"].collect do |testable_summary|
        summary_row = {
          project_path: testable_summary["ProjectPath"],
          target_name: testable_summary["TargetName"],
          test_name: testable_summary["TestName"],
          duration: testable_summary["Tests"].map { |current_test| current_test["Duration"] }.inject(:+),
          tests: unfold_tests(testable_summary["Tests"]).collect do |current_test|
            test_group, test_name = test_group_and_name(testable_summary, current_test, xcpretty_naming)
            current_row = {
              identifier: current_test["TestIdentifier"],
                 test_group: test_group,
                 name: test_name,
              object_class: current_test["TestObjectClass"],
              status: current_test["TestStatus"],
              guid: current_test["TestSummaryGUID"],
              duration: current_test["Duration"]
            }
            if current_test["FailureSummaries"]
              current_row[:failures] = current_test["FailureSummaries"].collect do |current_failure|
                {
                  file_name: current_failure['FileName'],
                  line_number: current_failure['LineNumber'],
                  message: current_failure['Message'],
                  performance_failure: current_failure['PerformanceFailure'],
                  failure_message: "#{current_failure['Message']} (#{current_failure['FileName']}:#{current_failure['LineNumber']})"
                }
              end
            end
            current_row
          end
        }
        summary_row[:number_of_tests] = summary_row[:tests].count
        summary_row[:number_of_failures] = summary_row[:tests].find_all { |a| (a[:failures] || []).count > 0 }.count
        summary_row
      end
    end
  end
end
