import SwiftUI

struct RecordingView: View {
    var workoutManager: WorkoutManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        workoutManager.currentHeartRate > 0
                            ? "\(Int(workoutManager.currentHeartRate))"
                            : "--"
                    )
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    Text("BPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastSample = workoutManager.lastSampleDate {
                    let elapsed = context.date.timeIntervalSince(lastSample)
                    Text("\(Int(elapsed))s ago")
                        .font(.caption2)
                        .foregroundStyle(elapsed > 10 ? .orange : .secondary)
                } else {
                    Text("waiting...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("\(workoutManager.currentSession?.sampleCount ?? 0) HR / \(workoutManager.locationSampleCount) GPS / \(workoutManager.accelerometerSampleCount) accel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if workoutManager.usingSimulatedData {
                    Label("Simulated data", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Button {
                    workoutManager.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
