import Foundation

print("MenuBarCalendar tests\n")

runLunarTests()
runSolarTermTests()
runFestivalTests()
runHolidayTests()
runFormatterTests()
runCalendarMonthTests()
runPreferenceTests()
runViewModelTests()
runHolidayFeedTests()
runLeapMonthConsistencyTests()

exit(TestRunner.report())
