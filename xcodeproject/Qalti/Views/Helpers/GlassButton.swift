//
//  GlassButton.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 13.05.2025.
//

import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    var primaryColor: Color
    var cornerRadii: RectangleCornerRadii = RectangleCornerRadii(20)
    var padding: CGFloat = 12
    var horizontalPadding: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, padding)
            .padding(.horizontal, horizontalPadding)
            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 2, y: 3) // Text shadow
            .background(
                ZStack {
                    // Blur background using SwiftUI's Material
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(Material.ultraThinMaterial)
                    
                    // Additional inner glow layer - very subtle
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(.clear)
                        .overlay(
                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                .blur(radius: 2)
                                .mask(
                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.white, .clear],
                                                startPoint: .init(x: 0.25, y: 0),
                                                endPoint: .init(x: 0.3, y: 1)
                                            )
                                        )
                                )
                        )
                        .padding(1)
                    
                    // Subtle gradient overlay based on primary color
                    LinearGradient(
                        gradient: Gradient(colors: [
                            primaryColor.opacity(0.3),
                            primaryColor.opacity(0.2)
                        ]),
                        startPoint: .init(x: 0.25, y: 0),
                        endPoint: .init(x: 0.3, y: 1)
                    )
                    
                    // Matte finish overlay
                    Color.white.opacity(0.05)
                    
                    // Inner glow from primary color
                    UnevenRoundedRectangle(cornerRadii: cornerRadii.adding(-1), style: .continuous)
                        .stroke(
                            primaryColor.opacity(0.6),
                            lineWidth: 1
                        )
                        .blur(radius: 2.5)
                        .padding(1)
                    
                    // More pronounced border - specular reflection with more color gradient
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.5),
                                    primaryColor.opacity(0.5).mix(Color.white.opacity(0.5), 0.3)
                                ]),
                                startPoint: .init(x: 0.25, y: 0),
                                endPoint: .init(x: 0.3, y: 1)
                            ),
                            lineWidth: 1.0
                        )
                }
            )
            .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous))

            // Double shadow for more depth
            .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

// Extension for applying the glass button style easily
extension View {
    func glassButtonStyle(
        primaryColor: Color,
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 12,
        horizontalPadding: CGFloat? = nil
    ) -> some View {
        self.buttonStyle(GlassButtonStyle(
            primaryColor: primaryColor,
            cornerRadii: RectangleCornerRadii(cornerRadius),
            padding: padding,
            horizontalPadding: horizontalPadding ?? padding * 2
        ))
    }

    func glassButtonStyle(
        primaryColor: Color,
        cornerRadii: RectangleCornerRadii,
        padding: CGFloat = 12,
        horizontalPadding: CGFloat? = nil
    ) -> some View {
        self.buttonStyle(GlassButtonStyle(
            primaryColor: primaryColor,
            cornerRadii: cornerRadii,
            padding: padding,
            horizontalPadding: horizontalPadding ?? padding * 2
        ))
    }
}

// MARK: - Preview
struct GlassButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background image
            AsyncImage(url: URL(string: "https://ichef.bbci.co.uk/images/ic/976xn/p09qmhq5.jpg")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
            } placeholder: {
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            VStack(spacing: 20) {
                Button("Primary Glass Button") {}
                    .glassButtonStyle(primaryColor: .blue)
                
                Button("Purple Glass Button") {}
                    .glassButtonStyle(primaryColor: .purple)
                
                Button("Green Glass Button") {}
                    .glassButtonStyle(primaryColor: .green)
                    
                Button("Red Glass Button") {}
                    .glassButtonStyle(primaryColor: .red, cornerRadius: 20)
                    
                Button {
                    // Action
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                }
                .glassButtonStyle(primaryColor: Color(red: 0.6, green: 0.6, blue: 0.6))
            }
            .foregroundColor(.white)
            .padding()
        }
        .ignoresSafeArea()
    }
}

extension RectangleCornerRadii {
    init(_ singleRadius: CGFloat) {
        self.init(topLeading: singleRadius, bottomLeading: singleRadius, bottomTrailing: singleRadius, topTrailing: singleRadius)
    }

    func adding(_ difference: CGFloat) -> Self {
        return RectangleCornerRadii(
            topLeading: topLeading + difference,
            bottomLeading: bottomLeading + difference,
            bottomTrailing: bottomTrailing + difference,
            topTrailing: topTrailing + difference
        )
    }
}
