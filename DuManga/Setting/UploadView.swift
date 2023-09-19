import SwiftUI

struct UploadView: View {

    @State var uploadViewModel = UploadViewModel()

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text("settings.host.upload.label")
                TextEditor(text: $uploadViewModel.urls)
                        .border(.secondary, width: 2)
                        .disableAutocorrection(true)
                        .padding()
                        .frame(maxHeight: geometry.size.height * 0.2)
                Button(action: {
                    Task {
                        await uploadViewModel.queueDownload()
                    }
                }, label: {
                    Text("settings.host.upload.action")
                            .font(.title)
                })
                        .buttonStyle(.borderedProminent)
                List {
                    ForEach(uploadViewModel.jobDetails.keys.sorted(), id: \.self) { key in
                        let detail = uploadViewModel.jobDetails[key]!
                        Section {
                            Label(title: {
                                VStack {
                                    Text(extractTitle(item: detail))
                                    Text(detail.message)
                                }
                            }, icon: {
                                if detail.isActive {
                                    ProgressView()
                                } else if detail.isSuccess {
                                    Image(systemName: "circle.fill")
                                            .foregroundColor(.green)
                                } else if detail.isError {
                                    Image(systemName: "circle.fill")
                                            .foregroundColor(.red)
                                } else {
                                    Image(systemName: "questionmark")
                                            .foregroundColor(.yellow)
                                }
                            })
                        } header: {
                            Text("Job ID: \(key)")
                        }
                    }
                    Text("settings.host.upload.note")
                            .font(.footnote)
                }

            }
            .task {
                repeat {
                    await uploadViewModel.checkJobStatus()
                    try? await Task.sleep(for: .seconds(5))
                } while (true)
            }
            .toolbar(.hidden, for: .tabBar)
        }
    }

    private func extractTitle(item: DownloadJob) -> String {
        if item.title.isEmpty {
            return item.url
        }
        return item.title
    }
}
