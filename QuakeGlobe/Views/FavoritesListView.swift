//
//  FavoritesListView.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import SwiftUI
import SwiftData

struct FavoritesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FavoriteQuake.time, order: .reverse) private var favorites: [FavoriteQuake]

    /// Linha tocada = pedido de fly-to; o ContentView cuida do resto.
    let onFly: (Earthquake) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "heart",
                        description: Text("Tap the heart on a quake's card to save it here.")
                    )
                } else {
                    List {
                        ForEach(favorites) { fav in
                            Button {
                                onFly(fav.earthquake)
                                dismiss()
                            } label: {
                                row(for: fav)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.black)
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func row(for fav: FavoriteQuake) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "M %.1f", fav.magnitude))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(fav.earthquake.severity.color)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(fav.place)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if fav.time > 0 {
                    Text(Date(timeIntervalSince1970: fav.time / 1000),
                         format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()

            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(favorites[index])
        }
        try? context.save()
    }
}
