import KsApi
import Prelude
import ReactiveCocoa
import ReactiveExtensions
import Result

public protocol DiscoveryPageViewModelInputs {
  /// Call with the sort provided to the view.
  func configureWith(sort sort: DiscoveryParams.Sort)

  /// Call when the filter is changed.
  func selectedFilter(params: DiscoveryParams)

  /// Call when the user taps on the activity sample.
  func tapped(activity activity: Activity)

  /// Call when the user taps on a project.
  func tapped(project project: Project)

  /// Call when the view appears.
  func viewDidAppear()

  /// Call when the view disappears.
  func viewDidDisappear(animated animated: Bool)

  /// Call when the view will appear.
  func viewWillAppear()

  /**
   Call from the controller's `tableView:willDisplayCell:forRowAtIndexPath` method.

   - parameter row:       The 0-based index of the row displaying.
   - parameter totalRows: The total number of rows in the table view.
   */
  func willDisplayRow(row: Int, outOf totalRows: Int)
}

public protocol DiscoveryPageViewModelOutputs {
  /// Emits a list of activities to be displayed in the sample.
  var activitiesForSample: Signal<[Activity], NoError> { get }

  /// Hack to emit when we should asynchronously reload the table view's data to properly display postcards.
  /// Hopefully in the future we can remove this when we can resolve postcard display issues.
  var asyncReloadData: Signal<Void, NoError> { get }

  /// Emits when we should focus on the first visible project
  var focusScreenReaderOnFirstProject: Signal<(), NoError> { get }

  /// Emits a project and ref tag that we should go to.
  var goToProject: Signal<(Project, RefTag), NoError> { get }

  /// Emits a project and update when should go to update.
  var goToProjectUpdate: Signal<(Project, Update), NoError> { get }

  /// Emits a list of projects that should be shown.
  var projects: Signal<[Project], NoError> { get }

  /// Emits a boolean that determines if projects are currently loading or not.
  var projectsAreLoading: Signal<Bool, NoError> { get }

  /// Emits a boolean that determines of the onboarding should be shown.
  var showOnboarding: Signal<Bool, NoError> { get }
}

public protocol DiscoveryPageViewModelType {
  var inputs: DiscoveryPageViewModelInputs { get }
  var outputs: DiscoveryPageViewModelOutputs { get }
}

public final class DiscoveryPageViewModel: DiscoveryPageViewModelType, DiscoveryPageViewModelInputs,
  DiscoveryPageViewModelOutputs {

  // swiftlint:disable function_body_length
  public init() {
    let paramsChanged = combineLatest(
      self.sortProperty.signal.ignoreNil(),
      self.selectedFilterProperty.signal.ignoreNil()
      )
      .map(DiscoveryParams.lens.sort.set)

    let isCloseToBottom = self.willDisplayRowProperty.signal.ignoreNil()
      .map { row, total in row >= total - 3 && row > 0 }
      .skipRepeats()
      .filter(isTrue)
      .ignoreValues()

    let isVisible = Signal.merge(
      self.viewDidAppearProperty.signal.mapConst(true),
      self.viewDidDisappearProperty.signal.mapConst(false)
      ).skipRepeats()

    let requestFirstPageWith = combineLatest(paramsChanged, isVisible)
      .filter { _, visible in visible }
      .map { params, _ in params }
      .skipRepeats()

    let paginatedProjects: Signal<[Project], NoError>
    let pageCount: Signal<Int, NoError>
    (paginatedProjects, self.projectsAreLoading, pageCount) = paginate(
      requestFirstPageWith: requestFirstPageWith,
      requestNextPageWhen: isCloseToBottom,
      clearOnNewRequest: true,
      valuesFromEnvelope: { $0.projects },
      cursorFromEnvelope: { $0.urls.api.moreProjects },
      requestFromParams: { AppEnvironment.current.apiService.fetchDiscovery(params: $0) },
      requestFromCursor: { AppEnvironment.current.apiService.fetchDiscovery(paginationUrl: $0) })

    self.projects = Signal.merge(
      paginatedProjects,
      self.selectedFilterProperty.signal.ignoreNil().skipRepeats().mapConst([])
      )
      .skipWhile { $0.isEmpty }
      .skipRepeats(==)

    self.asyncReloadData = self.projects.take(1).ignoreValues()

    let fetchActivityEvent = self.viewWillAppearProperty.signal
      .filter { _ in AppEnvironment.current.currentUser != nil }
      .switchMap { _ in
        AppEnvironment.current.apiService.fetchActivities(count: 1)
          .delay(AppEnvironment.current.apiDelayInterval, onScheduler: AppEnvironment.current.scheduler)
          .materialize()
    }

    let activitySampleTapped = self.tappedActivity.signal.ignoreNil()
      .filter { $0.category != .update }
      .map { $0.project }.ignoreNil()
      .map { ($0, RefTag.activitySample) }

    let projectCardTapped = paramsChanged
      .takePairWhen(self.tappedProject.signal.ignoreNil())
      .map { params, project in (project, refTag(fromParams: params, project: project)) }

    self.goToProject = Signal.merge(activitySampleTapped, projectCardTapped)

    self.goToProjectUpdate = self.tappedActivity.signal.ignoreNil()
      .filter { $0.category == .update }
      .flatMap { activity -> SignalProducer<(Project, Update), NoError> in
        guard let project = activity.project, update = activity.update else {
          return .empty
        }
        return SignalProducer(value: (project, update))
    }

    let activities = fetchActivityEvent.values().map { $0.activities }
      .skipRepeats(==)
      .map { $0.filter { activity in hasNotSeen(activity: activity) } }
      .on(next: { activities in saveSeen(activities: activities) })

    let clearActivitySampleOnLogout = self.viewWillAppearProperty.signal
      .filter { _ in AppEnvironment.current.currentUser == nil }

    let clearActivitySampleOnNavigate = Signal.merge(
      paramsChanged.mapConst(true),
      self.goToProject.mapConst(false),
      self.goToProjectUpdate.mapConst(false),
      self.viewDidDisappearProperty.signal.filter { animated in !animated }.mapConst(false),
      self.viewDidAppearProperty.signal.mapConst(true)
      )
      .takeWhen(self.viewDidDisappearProperty.signal)
      .filter(isTrue)

    self.activitiesForSample = Signal.merge(
      activities,
      clearActivitySampleOnLogout.mapConst([]),
      clearActivitySampleOnNavigate.mapConst([])
      )
      .skipRepeats(==)

    self.showOnboarding = combineLatest(
      self.viewWillAppearProperty.signal,
      self.sortProperty.signal.ignoreNil()
      )
      .map { _, sort in
        return AppEnvironment.current.currentUser == nil && sort == .Magic
      }
      .skipRepeats()

    requestFirstPageWith
      .takePairWhen(pageCount)
      .observeNext { params, page in
        AppEnvironment.current.koala.trackDiscovery(params: params, page: page)
    }

    let focusFirstProjectWhenProjectsLoad = pageCount
      .takeWhen(paginatedProjects)
      .filter { $0 == 1 }
      .ignoreValues()

    let focusFirstProjectWhenViewAppears = paginatedProjects
      .takeWhen(self.viewDidAppearProperty.signal)
      .filter { !$0.isEmpty }
      .ignoreValues()

    self.focusScreenReaderOnFirstProject = Signal.merge(
      focusFirstProjectWhenProjectsLoad,
      focusFirstProjectWhenViewAppears
    )
  }
  // swiftlint:enable function_body_length

  private let sortProperty = MutableProperty<DiscoveryParams.Sort?>(nil)
  public func configureWith(sort sort: DiscoveryParams.Sort) {
    self.sortProperty.value = sort
  }
  private let selectedFilterProperty = MutableProperty<DiscoveryParams?>(nil)
  public func selectedFilter(params: DiscoveryParams) {
    self.selectedFilterProperty.value = params
  }
  private let tappedActivity = MutableProperty<Activity?>(nil)
  public func tapped(activity activity: Activity) {
    self.tappedActivity.value = activity
  }
  private let tappedProject = MutableProperty<Project?>(nil)
  public func tapped(project project: Project) {
    self.tappedProject.value = project
  }
  private let viewDidAppearProperty = MutableProperty()
  public func viewDidAppear() {
    self.viewDidAppearProperty.value = ()
  }
  private let viewDidDisappearProperty = MutableProperty(false)
  public func viewDidDisappear(animated animated: Bool) {
    self.viewDidDisappearProperty.value = animated
  }
  private let viewWillAppearProperty = MutableProperty()
  public func viewWillAppear() {
    self.viewWillAppearProperty.value = ()
  }
  private let willDisplayRowProperty = MutableProperty<(row: Int, total: Int)?>(nil)
  public func willDisplayRow(row: Int, outOf totalRows: Int) {
    self.willDisplayRowProperty.value = (row, totalRows)
  }

  public let activitiesForSample: Signal<[Activity], NoError>
  public var asyncReloadData: Signal<Void, NoError>
  public let focusScreenReaderOnFirstProject: Signal<(), NoError>
  public let goToProject: Signal<(Project, RefTag), NoError>
  public let goToProjectUpdate: Signal<(Project, Update), NoError>
  public let projects: Signal<[Project], NoError>
  public let projectsAreLoading: Signal<Bool, NoError>
  public let showOnboarding: Signal<Bool, NoError>

  public var inputs: DiscoveryPageViewModelInputs { return self }
  public var outputs: DiscoveryPageViewModelOutputs { return self }
}

private func hasNotSeen(activity activity: Activity) -> Bool {
  return activity.id != AppEnvironment.current.userDefaults.lastSeenActivitySampleId
}

private func saveSeen(activities activities: [Activity]) -> () {
  activities.forEach { activity in
    AppEnvironment.current.userDefaults.lastSeenActivitySampleId = activity.id
  }
}

private func refTag(fromParams params: DiscoveryParams, project: Project) -> RefTag {

  if project.isPotdToday() {
    return .discoveryPotd
  } else if params.category != nil {
    return .categoryWithSort(params.sort ?? .Magic)
  } else if params.staffPicks == true {
    return .recommendedWithSort(params.sort ?? .Magic)
  } else if params.social == true {
    return .social
  }
  return RefTag.discovery
}
