import SwiftUI

struct WorkoutView: View {
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

                Text(
                    "\(workoutManager.heartRateSampleCount) HR"
                        + " / \(workoutManager.locationSampleCount) GPS"
                        + " / \(workoutManager.accelerometerSampleCount) accel"
                        + " / \(workoutManager.deviceMotionSampleCount) motion"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

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
