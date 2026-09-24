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
runAgendaTests()

exit(TestRunner.report())
