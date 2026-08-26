// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2025 The Linux Foundation
package fixture;

/** Calls into the core subproject. */
public final class App {
    private App() {
    }

    public static String run(final String name) {
        return Core.greet(name);
    }
}
