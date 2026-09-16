//
//  EnableInteractivePopGesture.swift
//  AppwinSupport
//
//  Re-enables the UIKit interactive pop (swipe from edge) when the system back
//  button is hidden, since `navigationBarBackButtonHidden(true)` disables it.
//

import SwiftUI
import UIKit

struct EnableInteractivePopGesture: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let nav = uiViewController.navigationController else { return }
            let gesture = nav.interactivePopGestureRecognizer
            gesture?.isEnabled = nav.viewControllers.count > 1
            gesture?.delegate = context.coordinator
            context.coordinator.navigationController = nav
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        /// Lets the edge swipe coexist with the chat ScrollView's gestures.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// Apply to a screen pushed with a custom back button.
    func enableInteractivePopGesture() -> some View {
        background(EnableInteractivePopGesture())
    }
}
