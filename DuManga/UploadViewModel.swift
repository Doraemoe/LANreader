import SwiftUI
import Logging

@Observable
class UploadViewModel {
    private static let logger = Logger(label: "UploadViewModel")

    var urls = ""
    var jobDetails: [Int: DownloadJob] = .init()

    private var processing = false

    private var service = LANraragiService.shared
    private var database = AppDatabase.shared

    @MainActor
    func queueDownload() async {
        for url in urls.split(whereSeparator: \.isNewline) {
            let processedUrl = url.trimmingCharacters(in: .whitespaces)
            if !processedUrl.isEmpty {
                do {
                    let response = try await service.queueUrlDownload(downloadUrl: String(url)).value
                    if response.success == 1 {
                        var downloadJob = DownloadJob(
                                id: response.job,
                                url: response.url,
                                title: "",
                                isActive: true,
                                isSuccess: false,
                                isError: false,
                                message: "",
                                lastUpdate: Date()
                        )
                        try? database.saveDownloadJob(&downloadJob)
                        jobDetails[response.job] = downloadJob
                    }
                } catch {
                    UploadViewModel.logger.error("failed to queue download job. url=\(url) \(error)")
                }
            }
        }
    }

    @MainActor
    func checkJobStatus() async {
        let downloadJobs: [DownloadJob]
        do {
            downloadJobs = try database.readAllDownloadJobs()
        } catch {
            UploadViewModel.logger.error("failed to retrieve download jobs from db. \(error)")
            downloadJobs = .init()
        }
        for job in downloadJobs {
            if job.lastUpdate.addingTimeInterval(3600) < Date() {
                _ = try? database.deleteDownloadJobs(job.id)
            }
            if !job.isSuccess && !job.isError {
                do {
                    let response = try await service.checkJobStatus(id: job.id).value
                    var downloadJob = response.toDownloadJob(url: job.url)
                    jobDetails[job.id] = downloadJob
                    do {
                        try database.saveDownloadJob(&downloadJob)
                    } catch {
                        UploadViewModel.logger.error("failed to save updated job to database. id=\(job.id), \(error)")
                    }
                } catch {
                    UploadViewModel.logger.error("failed to check job status. id=\(job.id) \(error)")
                }
            } else {
                jobDetails[job.id] = job
            }
        }
    }
}
