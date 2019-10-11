module Trainer
  module XCResult
    # Model attributes and relationships taken from running the following command:
    # xcrun xcresulttool formatDescription

    class AbstractObject
      attr_accessor :type
      def initialize(data)
        self.type = data["_type"]["_name"]
      end

      def fetch_value(data, key)
        return (data[key] || {})["_value"]
      end

      def fetch_values(data, key)
        return (data[key] || {})["_values"] || []
      end
    end

    # - ActionTestPlanRunSummaries
    #   * Kind: object
    #   * Properties:
    #     + summaries: [ActionTestPlanRunSummary]
    class ActionTestPlanRunSummaries < AbstractObject
      attr_accessor :summaries
      def initialize(data)
        self.summaries = fetch_values(data, "summaries").map do |summary_data|
          ActionTestPlanRunSummary.new(summary_data)
        end
        super
      end
    end

    # - ActionAbstractTestSummary
    #   * Kind: object
    #   * Properties:
    #     + name: String?
    class ActionAbstractTestSummary < AbstractObject
      attr_accessor :name
      def initialize(data)
        self.name = fetch_value(data, "name")
        super
      end
    end

    # - ActionTestPlanRunSummary
    #   * Supertype: ActionAbstractTestSummary
    #   * Kind: object
    #   * Properties:
    #     + testableSummaries: [ActionTestableSummary]
    class ActionTestPlanRunSummary < ActionAbstractTestSummary
      attr_accessor :testable_summaries
      def initialize(data)
        self.testable_summaries = fetch_values(data, "testableSummaries").map do |summary_data|
          ActionTestableSummary.new(summary_data)
        end
        super
      end
    end

    # - ActionTestableSummary
    #   * Supertype: ActionAbstractTestSummary
    #   * Kind: object
    #   * Properties:
    #     + projectRelativePath: String?
    #     + targetName: String?
    #     + testKind: String?
    #     + tests: [ActionTestSummaryIdentifiableObject]
    #     + diagnosticsDirectoryName: String?
    #     + failureSummaries: [ActionTestFailureSummary]
    #     + testLanguage: String?
    #     + testRegion: String?
    class ActionTestableSummary < ActionAbstractTestSummary
      attr_accessor :project_relative_path
      attr_accessor :target_name
      attr_accessor :test_kind
      attr_accessor :tests
      def initialize(data)
        self.project_relative_path = fetch_value(data, "projectRelativePath")
        self.target_name = fetch_value(data, "targetName")
        self.test_kind = fetch_value(data, "testKind")
        self.tests = fetch_values(data, "tests").map do |tests_data|
          ActionTestSummaryIdentifiableObject.create(tests_data, self)
        end
        super
      end

      def all_tests
        return tests.map(&:all_subtests).flatten
      end
    end

    # - ActionTestSummaryIdentifiableObject
    #   * Supertype: ActionAbstractTestSummary
    #   * Kind: object
    #   * Properties:
    #     + identifier: String?
    class ActionTestSummaryIdentifiableObject < ActionAbstractTestSummary
      attr_accessor :identifier
      attr_accessor :parent
      def initialize(data, parent)
        self.identifier = fetch_value(data, "identifier")
        self.parent = parent
        super(data)
      end

      def all_subtests
        raise "Not overridden"
      end

      def self.create(data, parent)
        type = data["_type"]["_name"]
        if type == "ActionTestSummaryGroup"
          return ActionTestSummaryGroup.new(data, parent)
        elsif type == "ActionTestMetadata"
          return ActionTestMetadata.new(data, parent)
        else
          raise "Unsupported type: #{type}"
        end
      end
    end

    # - ActionTestSummary
    # * Supertype: ActionTestSummaryIdentifiableObject
    # * Kind: object
    # * Properties:
    #   + testStatus: String
    #   + duration: Double
    #   + performanceMetrics: [ActionTestPerformanceMetricSummary]
    #   + failureSummaries: [ActionTestFailureSummary]
    #   + activitySummaries: [ActionTestActivitySummary]
    class ActionTestSummary < ActionTestSummaryIdentifiableObject
      attr_accessor :test_status
      attr_accessor :duration
      attr_accessor :activity_summaries
      def initialize(data, parent)
        self.test_status = fetch_value(data, "testStatus")
        self.duration = fetch_value(data, "duration")
        self.activity_summaries = fetch_values(data, "activitySummaries").map do |summary_data|
          ActionTestActivitySummary.new(summary_data)
        end
        super(data, parent)
      end
    end

    # - ActionTestActivitySummary
    # * Kind: object
    # * Properties:
    #   + title: String
    #   + activityType: String
    #   + uuid: String
    #   + start: Date?
    #   + finish: Date?
    #   + attachments: [ActionTestAttachment]
    #   + subactivities: [ActionTestActivitySummary]
    class ActionTestActivitySummary < AbstractObject
      attr_accessor :title
      attr_accessor :activity_type
      attr_accessor :uuid
      attr_accessor :start
      attr_accessor :finish
      attr_accessor :attachments
      attr_accessor :subactivities
      def initialize(data)
        self.title = fetch_value(data, "title")
        self.activity_type = fetch_value(data, "activityType")
        self.uuid = fetch_value(data, "uuid")
        self.start = fetch_value(data, "start")
        self.finish = fetch_value(data, "finish")
        self.attachments = fetch_values(data, "attachments").map do |attachment_data|
          ActionTestAttachment.new(attachment_data)
        end
        self.subactivities = fetch_values(data, "subactivities").map do |activity_data|
          ActionTestActivitySummary.new(activity_data)
        end
        super
      end

      def all_attachments
        return (attachments + subactivities.map(&:all_attachments)).flatten
      end
    end

    # - ActionTestAttachment
    # * Kind: object
    # * Properties:
    #   + uniformTypeIdentifier: String
    #   + name: String?
    #   + timestamp: Date?
    #   + userInfo: SortedKeyValueArray?
    #   + lifetime: String
    #   + inActivityIdentifier: Int
    #   + filename: String?
    #   + payloadRef: Reference?
    #   + payloadSize: Int
    class ActionTestAttachment < AbstractObject
      attr_accessor :uniform_type_identifier
      attr_accessor :name
      attr_accessor :timestamp
      attr_accessor :lifetime
      attr_accessor :in_activity_identifier
      attr_accessor :filename
      attr_accessor :payload_ref
      attr_accessor :payload_size
      def initialize(data)
        self.uniform_type_identifier = fetch_value(data, "uniformTypeIdentifier")
        self.name = fetch_value(data, "name")
        self.timestamp = fetch_value(data, "timestamp")
        self.lifetime = fetch_value(data, "lifetime")
        self.in_activity_identifier = fetch_value(data, "inActivityIdentifier")
        self.filename = fetch_value(data, "filename")
        self.payload_ref = Reference.new(data["payloadRef"]) if data["payloadRef"]
        self.payload_size = fetch_value(data, "payloadSize")
        super
      end
    end

    # - ActivityLogSection
    # * Kind: object
    # * Properties:
    #   + domainType: String
    #   + title: String
    #   + startTime: Date?
    #   + duration: Double
    #   + result: String?
    #   + subsections: [ActivityLogSection]
    #   + messages: [ActivityLogMessage]
    class ActivityLogSection < AbstractObject
      attr_accessor :domain_type
      attr_accessor :title
      attr_accessor :start_time
      attr_accessor :duration
      attr_accessor :result
      attr_accessor :subsections
      def initialize(data)
        self.domain_type = fetch_value(data, "domainType")
        self.title = fetch_value(data, "title")
        self.start_time = fetch_value(data, "startTime")
        self.duration = fetch_value(data, "duration")
        self.result = fetch_value(data, "result")
        self.subsections = fetch_values(data, "subsections").map do |data|
          ActivityLogSection.create(data)
        end.compact
        super
      end

      def self.create(data)
        type = data["_type"]["_name"]
        if type == "ActivityLogUnitTestSection"
          return ActivityLogUnitTestSection.new(data)
        elsif type == "ActivityLogMajorSection"
          return ActivityLogMajorSection.new(data)
        elsif type == "ActivityLogSection"
          return ActivityLogSection.new(data)
        else
          puts "Warning: Unsupported type: #{type}"
        end
      end

      # Returns all the ActivityLogUnitTestSection relevant to a specific test
      def all_test_logs
        return ([self] + subsections.map(&:all_test_logs)).flatten.select do |section|
          section.class == Trainer::XCResult::ActivityLogUnitTestSection && !section.test_name.nil?
        end
      end
    end

    # - ActivityLogMajorSection
    # * Supertype: ActivityLogSection
    # * Kind: object
    # * Properties:
    #   + subtitle: String
    class ActivityLogMajorSection < ActivityLogSection
      attr_accessor :subtitle
      def initialize(data)
        self.subtitle = fetch_value(data, "subtitle")
        super(data)
      end
    end


    # - ActivityLogUnitTestSection
    # * Supertype: ActivityLogSection
    # * Kind: object
    # * Properties:
    #   + testName: String?
    #   + suiteName: String?
    #   + summary: String?
    #   + emittedOutput: String?
    #   + performanceTestOutput: String?
    #   + testsPassedString: String?
    #   + runnablePath: String?
    #   + runnableUTI: String?
    class ActivityLogUnitTestSection < ActivityLogSection
      attr_accessor :test_name
      attr_accessor :suite_name
      attr_accessor :summary
      attr_accessor :emitted_output
      attr_accessor :performance_test_output
      attr_accessor :tests_passed_string
      attr_accessor :runnable_path
      attr_accessor :runnable_uti
      def initialize(data)
        self.test_name = fetch_value(data, "testName")
        self.suite_name = fetch_value(data, "suiteName")
        self.summary = fetch_value(data, "summary")
        self.emitted_output = fetch_value(data, "emittedOutput")
        self.performance_test_output = fetch_value(data, "performanceTestOutput")
        self.tests_passed_string = fetch_value(data, "testsPassedString")
        self.runnable_path = fetch_value(data, "runnablePath")
        self.runnable_uti = fetch_value(data, "runnableUTI")
        super(data)
      end
    end


    # - ActionTestSummaryGroup
    #   * Supertype: ActionTestSummaryIdentifiableObject
    #   * Kind: object
    #   * Properties:
    #     + duration: Double
    #     + subtests: [ActionTestSummaryIdentifiableObject]
    class ActionTestSummaryGroup < ActionTestSummaryIdentifiableObject
      attr_accessor :duration
      attr_accessor :subtests
      def initialize(data, parent)
        self.duration = fetch_value(data, "duration").to_f
        self.subtests = fetch_values(data, "subtests").map do |subtests_data|
          ActionTestSummaryIdentifiableObject.create(subtests_data, self)
        end
        super(data, parent)
      end

      def all_subtests
        return subtests.map(&:all_subtests).flatten
      end
    end

    # - ActionTestMetadata
    #   * Supertype: ActionTestSummaryIdentifiableObject
    #   * Kind: object
    #   * Properties:
    #     + testStatus: String
    #     + duration: Double?
    #     + summaryRef: Reference?
    #     + performanceMetricsCount: Int
    #     + failureSummariesCount: Int
    #     + activitySummariesCount: Int
    class ActionTestMetadata < ActionTestSummaryIdentifiableObject
      attr_accessor :test_status
      attr_accessor :duration
      attr_accessor :summary_ref
      attr_accessor :performance_metrics_count
      attr_accessor :failure_summaries_count
      attr_accessor :activity_summaries_count
      def initialize(data, parent)
        self.test_status = fetch_value(data, "testStatus")
        self.duration = fetch_value(data, "duration").to_f
        self.summary_ref = Reference.new(data["summaryRef"]) if data["summaryRef"]

        self.performance_metrics_count = fetch_value(data, "performanceMetricsCount")
        self.failure_summaries_count = fetch_value(data, "failureSummariesCount")
        self.activity_summaries_count = fetch_value(data, "activitySummariesCount")
        super(data, parent)
      end

      def all_subtests
        return [self]
      end

      def find_failure(failures)
        if self.test_status == "Failure"
          # Tries to match failure on test case name
          # Example TestFailureIssueSummary:
          #   producingTarget: "TestThisDude"
          #   test_case_name: "TestThisDude.testFailureJosh2()" (when Swift)
          #     or "-[TestThisDudeTests testFailureJosh2]" (when Objective-C)
          # Example ActionTestMetadata
          #   identifier: "TestThisDude/testFailureJosh2()" (when Swift)
          #     or identifier: "TestThisDude/testFailureJosh2" (when Objective-C)

          found_failure = failures.find do |failure|
            # Clean test_case_name to match identifier format
            # Sanitize for Swift by replacing "." for "/"
            # Sanitize for Objective-C by removing "-", "[", "]", and replacing " " for ?/
            sanitized_test_case_name = failure.test_case_name
                                              .tr(".", "/")
                                              .tr("-", "")
                                              .tr("[", "")
                                              .tr("]", "")
                                              .tr(" ", "/")
            self.identifier == sanitized_test_case_name
          end
          return found_failure
        else
          return nil
        end
      end
    end

    # - ActionsInvocationRecord
    #   * Kind: object
    #   * Properties:
    #     + metadataRef: Reference?
    #     + metrics: ResultMetrics
    #     + issues: ResultIssueSummaries
    #     + actions: [ActionRecord]
    #     + archive: ArchiveInfo?
    class ActionsInvocationRecord < AbstractObject
      attr_accessor :actions
      attr_accessor :issues
      def initialize(data)
        self.actions = fetch_values(data, "actions").map do |action_data|
          ActionRecord.new(action_data)
        end
        self.issues = ResultIssueSummaries.new(data["issues"])
        super
      end
    end

    # - ActionRecord
    #   * Kind: object
    #   * Properties:
    #     + schemeCommandName: String
    #     + schemeTaskName: String
    #     + title: String?
    #     + startedTime: Date
    #     + endedTime: Date
    #     + runDestination: ActionRunDestinationRecord
    #     + buildResult: ActionResult
    #     + actionResult: ActionResult
    class ActionRecord < AbstractObject
      attr_accessor :scheme_command_name
      attr_accessor :scheme_task_name
      attr_accessor :title
      attr_accessor :build_result
      attr_accessor :action_result
      def initialize(data)
        self.scheme_command_name = fetch_value(data, "schemeCommandName")
        self.scheme_task_name = fetch_value(data, "schemeTaskName")
        self.title = fetch_value(data, "title")
        self.build_result = ActionResult.new(data["buildResult"])
        self.action_result = ActionResult.new(data["actionResult"])
        super
      end
    end

    # - ActionResult
    #   * Kind: object
    #   * Properties:
    #     + resultName: String
    #     + status: String
    #     + metrics: ResultMetrics
    #     + issues: ResultIssueSummaries
    #     + coverage: CodeCoverageInfo
    #     + timelineRef: Reference?
    #     + logRef: Reference?
    #     + testsRef: Reference?
    #     + diagnosticsRef: Reference?
    class ActionResult < AbstractObject
      attr_accessor :result_name
      attr_accessor :status
      attr_accessor :issues
      attr_accessor :timeline_ref
      attr_accessor :log_ref
      attr_accessor :tests_ref
      attr_accessor :diagnostics_ref
      def initialize(data)
        self.result_name = fetch_value(data, "resultName")
        self.status = fetch_value(data, "status")
        self.issues = ResultIssueSummaries.new(data["issues"])

        self.timeline_ref = Reference.new(data["timelineRef"]) if data["timelineRef"]
        self.log_ref = Reference.new(data["logRef"]) if data["logRef"]
        self.tests_ref = Reference.new(data["testsRef"]) if data["testsRef"]
        self.diagnostics_ref = Reference.new(data["diagnosticsRef"]) if data["diagnosticsRef"]
        super
      end
    end

    # - Reference
    #   * Kind: object
    #   * Properties:
    #     + id: String
    #     + targetType: TypeDefinition?
    class Reference < AbstractObject
      attr_accessor :id
      attr_accessor :target_type
      def initialize(data)
        self.id = fetch_value(data, "id")
        self.target_type = TypeDefinition.new(data["targetType"]) if data["targetType"]
        super
      end
    end

    # - TypeDefinition
    #   * Kind: object
    #   * Properties:
    #     + name: String
    #     + supertype: TypeDefinition?
    class TypeDefinition < AbstractObject
      attr_accessor :name
      attr_accessor :supertype
      def initialize(data)
        self.name = fetch_value(data, "name")
        self.supertype = TypeDefinition.new(data["supertype"]) if data["supertype"]
        super
      end
    end

    # - DocumentLocation
    #   * Kind: object
    #   * Properties:
    #     + url: String
    #     + concreteTypeName: String
    class DocumentLocation < AbstractObject
      attr_accessor :url
      attr_accessor :concrete_type_name
      def initialize(data)
        self.url = fetch_value(data, "url")
        self.concrete_type_name = data["concreteTypeName"]["_value"]
        super
      end
    end

    # - IssueSummary
    #   * Kind: object
    #   * Properties:
    #     + issueType: String
    #     + message: String
    #     + producingTarget: String?
    #     + documentLocationInCreatingWorkspace: DocumentLocation?
    class IssueSummary < AbstractObject
      attr_accessor :issue_type
      attr_accessor :message
      attr_accessor :producing_target
      attr_accessor :document_location_in_creating_workspace
      def initialize(data)
        self.issue_type = fetch_value(data, "issueType")
        self.message = fetch_value(data, "message")
        self.producing_target = fetch_value(data, "producingTarget")
        self.document_location_in_creating_workspace = DocumentLocation.new(data["documentLocationInCreatingWorkspace"]) if data["documentLocationInCreatingWorkspace"]
        super
      end
    end

    # - ResultIssueSummaries
    #   * Kind: object
    #   * Properties:
    #     + analyzerWarningSummaries: [IssueSummary]
    #     + errorSummaries: [IssueSummary]
    #     + testFailureSummaries: [TestFailureIssueSummary]
    #     + warningSummaries: [IssueSummary]
    class ResultIssueSummaries < AbstractObject
      attr_accessor :analyzer_warning_summaries
      attr_accessor :error_summaries
      attr_accessor :test_failure_summaries
      attr_accessor :warning_summaries
      def initialize(data)
        self.analyzer_warning_summaries = fetch_values(data, "analyzerWarningSummaries").map do |summary_data|
          IssueSummary.new(summary_data)
        end
        self.error_summaries = fetch_values(data, "errorSummaries").map do |summary_data|
          IssueSummary.new(summary_data)
        end
        self.test_failure_summaries = fetch_values(data, "testFailureSummaries").map do |summary_data|
          TestFailureIssueSummary.new(summary_data)
        end
        self.warning_summaries = fetch_values(data, "warningSummaries").map do |summary_data|
          IssueSummary.new(summary_data)
        end
        super
      end
    end

    # - TestFailureIssueSummary
    #   * Supertype: IssueSummary
    #   * Kind: object
    #   * Properties:
    #     + testCaseName: String
    class TestFailureIssueSummary < IssueSummary
      attr_accessor :test_case_name
      def initialize(data)
        self.test_case_name = fetch_value(data, "testCaseName")
        super
      end

      def failure_message
        new_message = self.message
        if self.document_location_in_creating_workspace
          file_path = self.document_location_in_creating_workspace.url.gsub("file://", "")
          new_message += " (#{file_path})"
        end

        return new_message
      end
    end
  end
end
