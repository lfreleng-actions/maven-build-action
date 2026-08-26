// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2025 The Linux Foundation
package fixture;

/** Carries the lines only another subproject's test reaches. */
public final class Core {
    private Core() {
    }

    public static String greet(final String name) {
        if (name == null || name.isEmpty()) {
            return "hello, world";
        }
        return "hello, " + name;
    }
}
