// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2025 The Linux Foundation
package fixture;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** The reactor's only test. Every line it reaches in core lives here. */
public class AppTest {
    @Test
    public void greetsByName() {
        assertEquals("hello, ada", App.run("ada"));
    }

    @Test
    public void greetsTheWorld() {
        assertEquals("hello, world", App.run(""));
    }
}
