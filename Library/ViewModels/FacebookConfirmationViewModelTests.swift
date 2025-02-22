@testable import KsApi
@testable import Library
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

final class FacebookConfirmationViewModelTests: TestCase {
  let vm: FacebookConfirmationViewModelType = FacebookConfirmationViewModel()
  let displayEmail = TestObserver<String, Never>()
  let sendNewsletters = TestObserver<Bool, Never>()
  let showLogin = TestObserver<(), Never>()
  let logIntoEnvironment = TestObserver<AccessTokenEnvelope, Never>()
  let postNotification = TestObserver<Notification.Name, Never>()
  let showSignupError = TestObserver<String, Never>()

  override func setUp() {
    super.setUp()
    self.vm.outputs.displayEmail.observe(self.displayEmail.observer)
    self.vm.outputs.sendNewsletters.observe(self.sendNewsletters.observer)
    self.vm.outputs.showLogin.observe(self.showLogin.observer)
    self.vm.outputs.logIntoEnvironment.observe(self.logIntoEnvironment.observer)
    self.vm.outputs.postNotification.map { $0.name }.observe(self.postNotification.observer)
    self.vm.errors.showSignupError.observe(self.showSignupError.observer)
  }

  func testDisplayEmail_whenViewDidLoad() {
    self.vm.inputs.email("kittens@kickstarter.com")

    self.displayEmail.assertDidNotEmitValue("Email does not display")

    self.vm.inputs.viewDidLoad()

    self.displayEmail.assertValues(["kittens@kickstarter.com"], "Display email")
  }

  func testNewsletterSwitch_whenViewDidLoad() {
    self.sendNewsletters.assertDidNotEmitValue("Newsletter toggle does not emit")

    self.vm.inputs.viewDidLoad()

    self.sendNewsletters.assertValues([false], "Newsletter toggle emits false")

    XCTAssertEqual(
      [], self.segmentTrackingClient.events,
      "Newsletter toggle is not tracked on intital state"
    )
  }

  func testNewsletterSwitch_whenViewDidLoad_German() {
    withEnvironment(countryCode: "DE") {
      self.sendNewsletters.assertDidNotEmitValue("Newsletter toggle does not emit")

      self.vm.inputs.viewDidLoad()

      self.sendNewsletters.assertValues([false], "Newsletter toggle emits false")
    }
  }

  func testNewsletterSwitch_whenViewDidLoad_UK() {
    withEnvironment(countryCode: "UK") {
      self.sendNewsletters.assertDidNotEmitValue("Newsletter toggle does not emit")

      self.vm.inputs.viewDidLoad()

      self.sendNewsletters.assertValues([false], "Newsletter toggle emits false")

      XCTAssertEqual(
        [], self.segmentTrackingClient.events,
        "Newsletter toggle is not tracked on intital state"
      )
    }
  }

  func testNewsletterToggle() {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.sendNewslettersToggled(false)

    self.sendNewsletters.assertValues([false, false], "Newsletter is toggled off")

    self.vm.inputs.sendNewslettersToggled(true)

    self.sendNewsletters.assertValues([false, false, true], "Newsletter is toggled on")
  }

  func testCreateNewAccount_withoutNewsletterToggle() {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.facebookToken("PuRrrrrrr3848")
    self.vm.inputs.createAccountButtonPressed()

    scheduler.advance()

    self.logIntoEnvironment.assertValueCount(1, "Account successfully created")

    self.vm.inputs.environmentLoggedIn()

    self.postNotification.assertValues(
      [.ksr_sessionStarted],
      "Login notification posted."
    )
  }

  func testCreateNewAccount_withNewsletterToggle() {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.facebookToken("PuRrrrrrr3848")
    self.vm.inputs.sendNewslettersToggled(true)
    self.vm.inputs.createAccountButtonPressed()

    scheduler.advance()

    self.logIntoEnvironment.assertValueCount(1, "Account successfully created")

    self.vm.inputs.environmentLoggedIn()

    self.postNotification.assertValues(
      [.ksr_sessionStarted],
      "Login notification posted."
    )
  }

  func testCreateNewAccount_withError() {
    let error = ErrorEnvelope(
      errorMessages: ["Email address has an issue. If you are not sure why, please contact us."],
      ksrCode: nil,
      httpCode: 422,
      exception: nil
    )

    withEnvironment(apiService: MockService(signupError: error)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.facebookToken("Meowwwww4484848")
      self.vm.inputs.createAccountButtonPressed()

      scheduler.advance()

      self.logIntoEnvironment.assertValueCount(0, "Did not emit log into environment")
      self.showSignupError.assertValues(
        ["Email address has an issue. If you are not sure why, please contact us."]
      )
    }
  }

  func testCreateNewAccount_withDefaultError() {
    let error = ErrorEnvelope(
      errorMessages: [],
      ksrCode: nil,
      httpCode: 422,
      exception: nil
    )

    withEnvironment(apiService: MockService(signupError: error)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.facebookToken("Meowwwww4484848")
      self.vm.inputs.createAccountButtonPressed()

      scheduler.advance()

      self.logIntoEnvironment.assertValueCount(0, "Did not emit log into environment")
      self.showSignupError.assertValues(
        ["Couldn't log in with Facebook."]
      )
    }
  }

  func testShowLogin() {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.loginButtonPressed()

    self.showLogin.assertValueCount(1, "Show login")
  }
}
