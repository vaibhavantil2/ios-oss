@testable import KsApi
@testable import Library
@testable import ReactiveExtensions_TestHelpers
import Prelude
import ReactiveCocoa
import Result
import UIKit
import XCTest

internal final class DiscoveryPageViewModelTests: TestCase {
  private let vm: DiscoveryPageViewModelType = DiscoveryPageViewModel()

  private let activitiesForSample = TestObserver<[Activity], NoError>()
  private let asyncReloadData = TestObserver<Void, NoError>()
  private let focusScreenReaderOnFirstProject = TestObserver<(), NoError>()
  private let goToProject = TestObserver<Project, NoError>()
  private let goToRefTag = TestObserver<RefTag, NoError>()
  private let goToProjectUpdate = TestObserver<Update, NoError>()
  private let hasAddedProjects = TestObserver<Bool, NoError>()
  private let hasRemovedProjects = TestObserver<Bool, NoError>()
  private let projectsAreLoading = TestObserver<Bool, NoError>()
  private let showOnboarding = TestObserver<Bool, NoError>()

  internal override func setUp() {
    super.setUp()

    self.vm.outputs.activitiesForSample.observe(self.activitiesForSample.observer)
    self.vm.outputs.asyncReloadData.observe(self.asyncReloadData.observer)
    self.vm.outputs.focusScreenReaderOnFirstProject.observe(self.focusScreenReaderOnFirstProject.observer)
    self.vm.outputs.goToProject.map { $0.0 }.observe(self.goToProject.observer)
    self.vm.outputs.goToProject.map { $0.1 }.observe(self.goToRefTag.observer)
    self.vm.outputs.goToProjectUpdate.map { $0.1 }.observe(self.goToProjectUpdate.observer)
    self.vm.outputs.showOnboarding.observe(self.showOnboarding.observer)

    self.vm.outputs.projects
      .map { $0.count }
      .combinePrevious(0)
      .map { prev, next in next > prev }
      .observe(self.hasAddedProjects.observer)
    self.vm.outputs.projects
      .map { $0.count }
      .combinePrevious(0)
      .map { prev, next in next < prev }
      .observe(self.hasRemovedProjects.observer)
    self.vm.outputs.projectsAreLoading.observe(self.projectsAreLoading.observer)
  }

  func testPaginating() {
    self.vm.inputs.configureWith(sort: .Magic)
    self.scheduler.advance()

    self.hasAddedProjects.assertDidNotEmitValue("No projects load at first.")
    self.hasRemovedProjects.assertDidNotEmitValue("No projects load at first.")
    XCTAssertEqual([], self.trackingClient.events, "No events tracked at first.")

    self.vm.inputs.selectedFilter(.defaults)
    self.vm.inputs.viewDidAppear()
    self.scheduler.advance()

    self.asyncReloadData.assertValueCount(1, "Reload data when projects are first added.")
    self.hasAddedProjects.assertValues([true], "Projects are added.")
    self.hasRemovedProjects.assertValues([false], "Projects are not removed.")
    self.projectsAreLoading.assertValues([true, false], "Loading indicator toggles on/off.")
    XCTAssertEqual(["Loaded Discovery Results", "Discover List View"],
                   self.trackingClient.events,
                   "Event is tracked once projects load.")
    XCTAssertEqual([1, 1],
                   self.trackingClient.properties(forKey: "page", as: Int.self),
                   "First page property tracks.")

    // Scroll down a bit and advance scheduler
    self.vm.inputs.willDisplayRow(2, outOf: 10)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true], "No projects are added.")
    self.hasRemovedProjects.assertValues([false], "No projects are removed.")
    XCTAssertEqual(["Loaded Discovery Results", "Discover List View"],
                   self.trackingClient.events,
                   "No new events are tracked.")
    XCTAssertEqual([1, 1],
                   self.trackingClient.properties(forKey: "page", as: Int.self),
                   "No new properties are tracked.")

    // Scroll down to the bottom of the view and advanced scheduler
    self.vm.inputs.willDisplayRow(9, outOf: 10)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, true], "More projects are added from pagination.")
    self.hasRemovedProjects.assertValues([false, false], "No projects are removed.")
    self.projectsAreLoading.assertValues([true, false, true, false], "Loading indicator toggles on/off.")
    XCTAssertEqual(["Loaded Discovery Results", "Discover List View", "Loaded Discovery Results",
      "Discover List View"],
                   self.trackingClient.events,
                   "Another event is tracked.")
    XCTAssertEqual([1, 1, 2, 2],
                   self.trackingClient.properties(forKey: "page", as: Int.self),
                   "The second page property is tracked.")

    // Make scroll area increase in size, advanced scheduler
    self.vm.inputs.willDisplayRow(9, outOf: 20)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, true], "No projects are added.")
    self.hasRemovedProjects.assertValues([false, false], "No projects are removed.")
    XCTAssertEqual(["Loaded Discovery Results", "Discover List View", "Loaded Discovery Results",
      "Discover List View"],
                   self.trackingClient.events,
                   "No new events are tracked.")
    XCTAssertEqual([1, 1, 2, 2],
                   self.trackingClient.properties(forKey: "page", as: Int.self),
                   "No new properties are tracked.")

    // Change the filter params used
    self.vm.inputs.viewDidDisappear(animated: true)
    self.vm.inputs.selectedFilter(
      .defaults |> DiscoveryParams.lens.category .~ Category.art
    )
    self.vm.inputs.viewDidAppear()

    self.hasAddedProjects.assertValues([true, true, false], "No projects are added.")
    self.hasRemovedProjects.assertValues([false, false, true], "Projects are removed right away.")

    // Advance scheduler so that the API request is made
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, true, false, true], "Projects are added.")
    self.hasRemovedProjects.assertValues([false, false, true, false], "Projects are not removed.")
    self.projectsAreLoading.assertValues([true, false, true, false, true, false],
                                         "Loading indicator toggles on/off.")
    XCTAssertEqual(["Loaded Discovery Results", "Discover List View", "Loaded Discovery Results",
      "Discover List View", "Loaded Discovery Results", "Discover List View"],
                   self.trackingClient.events,
                   "Another event is tracked.")
    XCTAssertEqual([1, 1, 2, 2, 1, 1],
                   self.trackingClient.properties(forKey: "page", as: Int.self),
                   "The first page property is tracked.")

    // Scroll to the end of the list and advance the scheduler.
    self.vm.inputs.willDisplayRow(18, outOf: 20)
    self.vm.inputs.willDisplayRow(19, outOf: 20)
    self.vm.inputs.willDisplayRow(20, outOf: 20)
    self.scheduler.advance()

    self.asyncReloadData.assertValueCount(1, "View is only reloaded once in the beginning.")
    self.hasAddedProjects.assertValues([true, true, false, true, true],
                                       "Projects are added.")
    self.hasRemovedProjects.assertValues([false, false, true, false, false],
                                         "Projects are not removed.")
    self.projectsAreLoading.assertValues([true, false, true, false, true, false, true, false],
                                         "Loading indicator toggles on/off.")
    XCTAssertEqual(["Loaded Discovery Results", "Discover List View", "Loaded Discovery Results",
      "Discover List View", "Loaded Discovery Results", "Discover List View", "Loaded Discovery Results",
      "Discover List View"],
                   self.trackingClient.events,
                   "Another event is tracked.")
    XCTAssertEqual([1, 1, 2, 2, 1, 1, 2, 2],
                   self.trackingClient.properties(forKey: "page", as: Int.self),
                   "The second page property is tracked.")
  }

  /**
   Tests how changing filters affects loading projects when the view is visible and hidden.
   */
  func testViewLifecycle() {
    // Configure and load up view model
    self.vm.inputs.configureWith(sort: .Magic)
    self.vm.inputs.viewDidAppear()
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([])

    // Select initial filter
    self.vm.inputs.selectedFilter(.defaults)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true], "Projects load after the filter is changed.")

    // Navigate away from page
    self.vm.inputs.viewDidDisappear(animated: true)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true], "Nothing changes when navigating away from view.")

    // Change filter
    self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.staffPicks .~ true)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, false],
                                       "Changing filters while away from view clears projects immediately.")

    // Change filter again
    self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.starred .~ true)
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, false],
                                       "Changing filter again does not do anything.")

    // Come back to page
    self.vm.inputs.viewDidAppear()
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, false, true], "Projects load once the view appears again.")

    // Navigate away and back
    self.vm.inputs.viewDidDisappear(animated: true)
    self.vm.inputs.viewDidAppear()
    self.scheduler.advance()

    self.hasAddedProjects.assertValues([true, false, true],
                                       "Switch away from the view and coming back doesn't do anything")
  }

  func testGoToProject() {
    let potdAt = AppEnvironment.current.calendar.startOfDayForDate(NSDate()).timeIntervalSince1970
    let project = Project.template
    let potd = project
      |> Project.lens.id %~ { $0 + 1 }
      |> Project.lens.dates.potdAt .~ potdAt

    self.vm.inputs.configureWith(sort: .Magic)
    self.vm.inputs.viewDidAppear()
    self.vm.inputs.selectedFilter(.defaults)
    self.scheduler.advance()

    self.vm.inputs.tapped(project: project)

    self.goToProject.assertValues([project])
    self.goToRefTag.assertValues([.discovery], "Go to the project with discovery ref tag.")

    self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.category .~ Category.art)
    self.vm.inputs.tapped(project: project)

    self.goToProject.assertValues([project, project])
    self.goToRefTag.assertValues([.discovery, .categoryWithSort(.Magic)],
                                 "Go to the project with the category sort ref tag.")

    self.vm.inputs.tapped(project: potd)

    self.goToProject.assertValues([project, project, potd])
    self.goToRefTag.assertValues([.discovery, .categoryWithSort(.Magic), .discoveryPotd],
                                 "Go to the project with the POTD ref tag.")

    self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.staffPicks .~ true)
    self.vm.inputs.tapped(project: project)

    self.goToProject.assertValues([project, project, potd, project])
    self.goToRefTag.assertValues(
      [.discovery, .categoryWithSort(.Magic), .discoveryPotd, .recommendedWithSort(.Magic)],
      "Go to the project with the recommended sort ref tag."
    )

    self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.social .~ true)
    self.vm.inputs.tapped(project: project)

    self.goToProject.assertValues([project, project, potd, project, project])
    self.goToRefTag.assertValues(
      [.discovery, .categoryWithSort(.Magic), .discoveryPotd, .recommendedWithSort(.Magic), .social],
      "Go to the project with the social ref tag."
    )

    let activityProject = Project.template
    let activity = .template |> Activity.lens.project .~ activityProject

    self.vm.inputs.tapped(activity: activity)
    self.goToProject.assertValues([project, project, potd, project, project, activityProject])
    self.goToRefTag.assertValues(
      [.discovery, .categoryWithSort(.Magic), .discoveryPotd, .recommendedWithSort(.Magic), .social,
        .activitySample],
      "Go to the project with the social ref tag."
    )
  }

  func testGoToProjectUpdate() {
    let update = Update.template

    let activity = .template
      |> Activity.lens.category .~ .update
      |> Activity.lens.project .~ Project.template
      |> Activity.lens.update .~ update

    self.vm.inputs.tapped(activity: activity)
    self.goToProjectUpdate.assertValues([update])
  }

  func testShowActivitySample() {
    let activity1 = .template
      |> Activity.lens.id .~ 111

    let activity2 = .template
      |> Activity.lens.id .~ 222

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))

    withEnvironment(apiService: MockService(fetchActivitiesResponse: [activity1])) {
      self.vm.inputs.configureWith(sort: .Magic)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()
      self.scheduler.advance()

      self.activitiesForSample.assertValues([[activity1]], "Activity sample is shown.")

      // Change the filter.
      self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.category .~ Category.art)
      self.vm.inputs.viewDidDisappear(animated: true)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()

      self.activitiesForSample.assertValues([[activity1], []], "Activity sample is hidden.")

      // Change the filter again.
      self.vm.inputs.selectedFilter(.defaults |> DiscoveryParams.lens.starred .~ true)
      self.vm.inputs.viewDidDisappear(animated: true)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()

      self.activitiesForSample.assertValues([[activity1], []], "Activity sample is still hidden.")

      withEnvironment(apiService: MockService(fetchActivitiesResponse: [activity2])) {
        self.vm.inputs.viewWillAppear()
        self.vm.inputs.viewDidAppear()
        self.scheduler.advance()

        self.activitiesForSample.assertValues([[activity1], [], [activity2]],
                                              "New activity sample is shown.")
      }
    }
  }

  func testActivitySampleWithLifecycle() {
    let activity = Activity.template

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))

    withEnvironment(apiService: MockService(fetchActivitiesResponse: [activity])) {
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()
      self.scheduler.advance()

      self.activitiesForSample.assertValues([[activity]], "Activity sample is shown.")

      // Tap on activity to go to project screen, then close project screen.
      self.vm.inputs.tapped(activity: activity)
      self.vm.inputs.viewDidDisappear(animated: true)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()

      self.activitiesForSample.assertValues([[activity]], "Activity sample is still shown.")

      // Change tab.
      self.vm.inputs.viewDidDisappear(animated: false)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()

      self.activitiesForSample.assertValues([[activity]], "Activity sample is still shown.")

      // Swipe half way to new sort, but return to same sort.
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()

      self.activitiesForSample.assertValues([[activity]], "Activity sample is still shown.")

      // Swipe to new sort, swipe back.
      self.vm.inputs.viewDidDisappear(animated: true)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()

      self.activitiesForSample.assertValues([[activity], []], "Activity sample is cleared.")
    }
  }

  func testClearActivitiesWhenLoggedOut() {
    let activity = .template
      |> Activity.lens.id .~ 111

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))

    withEnvironment(apiService: MockService(fetchActivitiesResponse: [activity])) {
      self.vm.inputs.configureWith(sort: .Magic)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()
      self.scheduler.advance()

      self.activitiesForSample.assertValues([[activity]], "Activity sample is shown.")
    }

    // Switch to profile tab to log out.
    self.vm.inputs.viewDidDisappear(animated: false)
    AppEnvironment.logout()
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidAppear()

    self.activitiesForSample.assertValues([[activity], []],
                                          "Activities are cleared out when logging out.")
  }

  func testShowOnboarding_LoggedOutOnMagic() {
    self.vm.inputs.configureWith(sort: .Magic)
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidAppear()
    self.vm.inputs.selectedFilter(.defaults)

    self.showOnboarding.assertValues([true])
  }

  func testShowOnboarding_LoggedOutOnNonMagic() {
    self.vm.inputs.configureWith(sort: .Popular)
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidAppear()
    self.vm.inputs.selectedFilter(.defaults)

    self.showOnboarding.assertValues([false])
  }

  func testShowOnboarding_LoggedIn() {
    withEnvironment(currentUser: .template) {
      self.vm.inputs.configureWith(sort: .Magic)
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidAppear()
      self.vm.inputs.selectedFilter(.defaults)

      self.showOnboarding.assertValues([false])
    }
  }

  func testFocusScreenReaderOnFirstProject() {
    self.vm.inputs.configureWith(sort: .Magic)
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidAppear()
    self.vm.inputs.selectedFilter(.defaults)

    self.focusScreenReaderOnFirstProject.assertValueCount(0)

    self.scheduler.advance()

    self.focusScreenReaderOnFirstProject.assertValueCount(1)

    self.vm.inputs.viewDidDisappear(animated: true)
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidAppear()

    self.focusScreenReaderOnFirstProject.assertValueCount(2)

    self.vm.inputs.willDisplayRow(9, outOf: 10)
    self.scheduler.advance()

    self.focusScreenReaderOnFirstProject.assertValueCount(2)
  }
}
