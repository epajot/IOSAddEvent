//
//  CalEventManager.swift v.0.2.4
//  IOSAddEvent
//
//  Created by Rudolf Farkas on 05.09.19.
//  Copyright © 2019 Eric PAJOT. All rights reserved.
//

import EventKit

extension EKAuthorizationStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
            @unknown default:
            fatalError()
        }
    }
}

enum CalEventError: Error {
    case accessDenied
    case calendarNotFound
    case noEventsFoundInCalendar
    case failedToSaveEventInCalendar
    case unknownError
}

extension EKEvent {
    var brief: String {
        var brf = ""
        if title != nil { brf += title }
        if startDate != nil { brf += " \(startDate!)" }
        if endDate != nil { brf += " to \(endDate!)" }
        if calendar != nil { brf += " in \(calendar!.title)" }
        return "\(brf)"
    }
}

/// Wrapper over EventKit
class CalEventManager: NSObject {
    static let shared = CalEventManager()

    var eventStore = EKEventStore()
    var authorized = false

    private override init() {
        super.init()
        updateAuthorization()
    }

    private func updateAuthorization() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            authorized = true
            printClassAndFunc(info: "authorized")
        case .denied:
            authorized = false
            printClassAndFunc(info: "authorization denied")
        case .notDetermined:
            eventStore.requestAccess(to: .event, completion: { (granted: Bool, _: Error?) -> Void in
                if granted {
                    self.authorized = true
                    self.printClassAndFunc(info: "authorization granted")
                } else {
                    self.authorized = false
                    self.printClassAndFunc(info: "authorization denied")
                }
            })
        default:
            authorized = false
            printClassAndFunc(info: "authorization not obtained")
        }
    }

    private func getEventsFromCalendarAuthorized(title: String, callback: ((Result<[EKEvent], CalEventError>) -> Void)) {
        guard let calendar = getCalendar(title: title) else {
//            printClassAndFunc(info: "*** calendar \(title) not found")
            callback(.failure(.calendarNotFound))
            return
        }
        printClassAndFunc(info: "calendar \(title) found")
        let events = getEvents(calendar: calendar)
        callback(.success(events))
    }

    /// Gets events from calendar and adds to bookings a booking for each event
    ///
    /// - Parameter title: calendar title
    func getEventsFromCalendar(title: String, callback: @escaping ((Result<[EKEvent], CalEventError>) -> Void)) {
        getAllCalendars { result in
            switch result {
            case let .success(calendars):
                self.printClassAndFunc(info: "calendars.count= \(calendars.count)")
                let filtered = calendars.filter({ $0.title == title })
                if filtered.count > 0 {
                    let calendar = filtered[0]
                    self.printClassAndFunc(info: "calendar \(calendar.title) found")
                    let events = self.getEvents(calendar: calendar)
                    self.printClassAndFunc(info: "events.count= \(events.count)")
                    callback(.success(events))
                } else {
                    self.printClassAndFunc(info: "calendar \(title) not found")
                    callback(.failure(.calendarNotFound))
                }
            case let .failure(error):
                self.printClassAndFunc(info: "error= \(error)")
                callback(.failure(error))
            }
        }
    }

    /// Check authorization for adding calendar events and insert event into calendar
    ///
    /// - Parameters:
    ///   - userName: user name
    ///   - calendarTitle: calendar title, e.g. "Code_Cal"
    func insertCalEvent(userName: String, calendarTitle: String, completion: @escaping ((Result<EKEvent, CalEventError>) -> Void)) {
        if authorized {
            printClassAndFunc(info: "AUTHORIZED")
            insertEvent(store: eventStore, userName: userName, calendarTitle: calendarTitle, completion: completion)
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized:
                authorized = true
                insertEvent(store: eventStore, userName: userName, calendarTitle: calendarTitle, completion: completion)
            case .denied:
                //            printClassAndFunc(info: "Access denied")
                completion(.failure(.accessDenied))
            case .notDetermined:
                eventStore.requestAccess(to: .event, completion: { (granted: Bool, _: Error?) -> Void in
                    if granted {
                        self.authorized = true
                        self.insertEvent(store: self.eventStore, userName: userName, calendarTitle: calendarTitle, completion: completion)
                    } else {
                        //                    self?.printClassAndFunc(info: "Access denied")
                        completion(.failure(.accessDenied))
                    }
                })
            default:
                //            printClassAndFunc(info: "Case default")
                completion(.failure(.unknownError))
            }
        }
    }

    /// Insert event into calendar
    ///
    /// - Parameters:
    ///   - userName: user name
    ///   - calendarTitle: calendar title, e.g. "Code_Cal"
    private func insertEvent(store: EKEventStore, userName: String, calendarTitle: String, completion: ((Result<EKEvent, CalEventError>) -> Void)) {
        //        printClassAndFunc(info: "")

        let calendars = store.calendars(for: .event)

        for calendar in calendars {
//            printClassAndFunc(info: "Calendar: \(calendar)")
            if calendar.title == calendarTitle {
                let startDate = Date()
                let endDate = startDate.addingTimeInterval(2 * 60 * 60)

                let event = EKEvent(eventStore: store)
                event.calendar = calendar

                event.title = userName
                event.startDate = startDate
                event.endDate = endDate

                do {
                    try store.save(event, span: .thisEvent)
                    completion(.success(event))
                    return
                } catch {
                    completion(.failure(.failedToSaveEventInCalendar))
                    return
                }
            }
        }
        completion(.failure(.calendarNotFound))
    }

    /// Get calendars from the event store
    ///
    /// - Returns: calendars in the event store
    func getCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event)
    }

    /// Find calendar by its title
    ///
    /// - Parameter title:
    /// - Returns: calendar, or nil if not found
    func getCalendar(title: String) -> EKCalendar? {
        let calendars = getCalendars()
        let calendars1 = calendars.filter({ $0.title == title })
        if calendars1.count > 0 {
            return calendars[0]
        } else {
            return nil
        }
    }

    /// Load events from calendar
    ///
    /// Note: returns events within the year 2109, for now
    ///
    /// - Parameter calendar: target calendar
    func getEvents(calendar: EKCalendar) -> [EKEvent] {
        // Create a date formatter instance to use for converting a string to a date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Create start and end date NSDate instances to build a predicate for which events to select
        let startDate = dateFormatter.date(from: "2019-01-01")
        let endDate = dateFormatter.date(from: "2019-12-31")

        if let startDate = startDate, let endDate = endDate {
//            let eventStore = EKEventStore()

            // Use an event store instance to create and properly configure an NSPredicate
            let eventsPredicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])

            // Use the configured NSPredicate to find and return events in the store that match
            let events = eventStore.events(matching: eventsPredicate).sorted {
                (e1: EKEvent, e2: EKEvent) -> Bool in
                return e1.startDate.compare(e2.startDate) == ComparisonResult.orderedAscending
            }

//            printClassAndFunc(info: "events.count=\(events.count)")
//            for event in events {
//                printClassAndFunc(info: "events.count=\(event.brief)")
//            }
            return events
        }
        return []
    }

    /// Check authorization for getting calendars and get all calendars
    ///
    func getAllCalendars(completion: @escaping ((Result<[EKCalendar], CalEventError>) -> Void)) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            getAllCalendarsAuthorized(completion: completion)
        case .denied:
            completion(.failure(.accessDenied))
        case .notDetermined:
            eventStore.requestAccess(to: .event, completion: { (granted: Bool, _: Error?) -> Void in
                if granted {
                    self.getAllCalendarsAuthorized(completion: completion)
                } else {
                    completion(.failure(.accessDenied))
                }
            })
        default:
            completion(.failure(.unknownError))
        }
    }

    private func getAllCalendarsAuthorized(completion: ((Result<[EKCalendar], CalEventError>) -> Void)) {
        let calendars = eventStore.calendars(for: .event)
        printClassAndFunc(info: "calendars.count=\(calendars.count)")
        completion(.success(calendars))
    }
}
