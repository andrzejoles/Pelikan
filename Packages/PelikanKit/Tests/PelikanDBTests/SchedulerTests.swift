import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("DBMS Scheduler na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct SchedulerTests {
    @Test("Zadanie: SQL tworzenia, odczyt do edycji, zmiana atrybutów, uruchomienie, przebiegi z raportem, DDL, usunięcie; drzewo obiektów")
    func jobLifecycle() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let owner = TestDatabase.config!.user.uppercased()
        _ = try? await s.execute("begin dbms_scheduler.drop_job('PELIKAN_JOB', force => true); end;")
        var job = SchedulerJob(name: "PELIKAN_JOB", action: "begin null; end;")
        job.repeatInterval = "FREQ=DAILY;BYHOUR=3"
        job.startDate = Date(timeIntervalSince1970: 2_000_000_000)
        job.enabled = false
        job.comments = "Pelikan test"
        _ = try await s.execute(Scheduler.createSQL(job))
        let read = try await Scheduler.job(owner: owner, name: "PELIKAN_JOB", in: s)
        #expect(read.action == job.action && read.repeatInterval == job.repeatInterval && read.comments == job.comments && !read.enabled)
        #expect(read.startDate == job.startDate)
        var changed = read
        changed.repeatInterval = "FREQ=HOURLY"
        changed.comments = "zmienione"
        let alter = Scheduler.alterSQL(from: read, to: changed)
        #expect(alter.contains("repeat_interval") && !alter.contains("job_action"))
        _ = try await s.execute(alter)
        #expect(try await Scheduler.job(owner: owner, name: "PELIKAN_JOB", in: s).repeatInterval == "FREQ=HOURLY")
        _ = try await s.execute("begin dbms_scheduler.run_job('PELIKAN_JOB', use_current_session => true); end;")
        let runs = try await Scheduler.runs(Scheduler.RunReport.standard[0], job: "PELIKAN_JOB", in: s)
        #expect(runs.rows.contains { $0[runs.columns.firstIndex(of: "STATUS")!] == "SUCCEEDED" })
        #expect(try await Scheduler.runs(Scheduler.RunReport.standard[1], job: "PELIKAN_JOB", in: s).rows.isEmpty)
        #expect(try await Scheduler.ddl(owner: owner, name: "PELIKAN_JOB", in: s).uppercased().contains("CREATE_JOB"))
        let jobs = try await Scheduler.objects(.jobs, in: s)
        #expect(jobs.contains { $0.name == "PELIKAN_JOB" && $0.state == "DISABLED" })
        for k in SchedulerObjectKind.allCases { _ = try await Scheduler.objects(k, in: s) }
        _ = try await Scheduler.running(in: s)
        _ = try await s.execute(Scheduler.dropSQL(.jobs, owner: owner, name: "PELIKAN_JOB", force: true))
        #expect(try await Scheduler.objects(.jobs, in: s).contains { $0.name == "PELIKAN_JOB" } == false)
    }
}
