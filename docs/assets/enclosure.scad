// Vitrine - Pepper's Ghost Enclosure
// OpenSCAD model for 3D printing
//
// Usage:
//   1. Open this file in OpenSCAD (https://openscad.org/)
//   2. Select the part to print by changing `RENDER_PART`
//   3. Export as STL (F6 → File → Export as STL)
//
// Design:
//   - Display unit (PI5-CASE-TD2) is mounted face-up on M2.5 standoffs
//   - Pi 5 bump and cables are fully contained inside the enclosure
//   - Half mirror rests on small support tabs at 45 degrees
//   - Lid is removable (magnet-attached, not glued)

/* [Render Settings] */
// Which part to render for STL export
RENDER_PART = "preview"; // [preview, body, lid, mirror_tab]

/* [Enclosure Dimensions] */
// Internal dimensions (mm)
inner_width  = 140;  // left-right (viewer perspective)
inner_depth  = 210;  // front-back
inner_height = 230;  // bottom-top (standoff 30 + case 42 + mirror space ~155 + margin)

// Wall thickness (mm)
wall = 3;

/* [Display Unit - PI5-CASE-TD2] */
// Case outer dimensions
case_width  = 125.58;
case_depth  = 194.66;
case_total_h = 42.07;  // total height including Pi bump
case_base_h  = 12.16;  // back plate thickness (flat area with M2.5 holes)

// M2.5 mounting holes on case back (from drawing)
m25_spacing_x = 175.00;  // horizontal spacing
m25_spacing_y = 110.60;  // vertical spacing
m25_inset_x   = 9.83;    // from case edge to hole center
m25_inset_y   = 7.49;    // from case edge to hole center

// Pi 5 bump dimensions (approximate from drawing)
pi_bump_w   = 94.25;
pi_bump_d   = 60;
pi_bump_h   = case_total_h - case_base_h;  // ~29.91mm

/* [Standoffs] */
standoff_h = 30;    // M2.5 standoff height (must be >= pi_bump_h)
standoff_r = 4;     // standoff outer radius
m25_hole_r = 1.4;   // M2.5 screw hole radius

/* [Viewing Window] */
window_width  = 120;
window_height = 150;
// Window bottom edge: above standoffs + case, showing mirror reflection area
window_offset_bottom = standoff_h + case_total_h + 5;

/* [Ventilation] */
vent_slot_w    = 25;
vent_slot_h    = 3;
vent_rows      = 3;
vent_cols      = 2;
vent_spacing_h = 7;
vent_spacing_w = 40;

/* [Cable Hole] */
cable_hole_w = 24;
cable_hole_h = 14;
cable_hole_r = 3;
// Cable hole vertical position: in the standoff/Pi area
cable_hole_z = standoff_h / 2;

/* [Half Mirror] */
mirror_thickness = 3;
// Mirror rests above the display unit (with clearance for case edges)
mirror_start_z = standoff_h + case_total_h + 10;  // = 82mm from bottom
mirror_projection = 155;  // active display area length

/* [Magnet Recesses] */
magnet_r = 4;     // magnet diameter 6-8mm -> radius 4mm with clearance
magnet_depth = 2; // magnet thickness
magnet_inset = 10; // from inner corner

// ============================================================
// Calculated values
// ============================================================
outer_width  = inner_width + wall * 2;   // 146mm
outer_depth  = inner_depth + wall * 2;   // 216mm
outer_height = inner_height + wall;      // body: open top

// M2.5 hole positions relative to enclosure origin
// Case is centered in the enclosure
case_offset_x = (outer_width - case_width) / 2;
case_offset_y = (outer_depth - case_depth) / 2;

// ============================================================
// Modules
// ============================================================

module rounded_box(w, d, h, r=2) {
    hull() {
        for (x = [r, w-r], y = [r, d-r]) {
            translate([x, y, 0])
                cylinder(h=h, r=r, $fn=20);
        }
    }
}

module vent_slots() {
    total_w = (vent_cols - 1) * vent_spacing_w + vent_slot_w;
    start_x = (inner_width - total_w) / 2 + wall;
    start_z = wall + standoff_h - 5;

    for (col = [0:vent_cols-1], row = [0:vent_rows-1]) {
        translate([
            start_x + col * vent_spacing_w,
            0,
            start_z + row * vent_spacing_h
        ])
            cube([vent_slot_w, wall + 1, vent_slot_h]);
    }
}

module cable_hole() {
    translate([
        (outer_width - cable_hole_w) / 2,
        0,
        wall + cable_hole_z
    ])
        hull() {
            translate([cable_hole_r, 0, cable_hole_r])
                rotate([-90, 0, 0])
                    cylinder(h=wall+1, r=cable_hole_r, $fn=16);
            translate([cable_hole_w - cable_hole_r, 0, cable_hole_r])
                rotate([-90, 0, 0])
                    cylinder(h=wall+1, r=cable_hole_r, $fn=16);
            translate([cable_hole_r, 0, cable_hole_h - cable_hole_r])
                rotate([-90, 0, 0])
                    cylinder(h=wall+1, r=cable_hole_r, $fn=16);
            translate([cable_hole_w - cable_hole_r, 0, cable_hole_h - cable_hole_r])
                rotate([-90, 0, 0])
                    cylinder(h=wall+1, r=cable_hole_r, $fn=16);
        }
}

module viewing_window() {
    wr = 3;
    translate([
        (outer_width - window_width) / 2,
        0,
        wall + window_offset_bottom
    ])
        hull() {
            for (x = [wr, window_width - wr], z = [wr, window_height - wr]) {
                translate([x, -1, z])
                    rotate([-90, 0, 0])
                        cylinder(h=wall+2, r=wr, $fn=16);
            }
        }
}

module standoff_positions() {
    // M2.5 hole positions based on PI5-CASE-TD2 drawing
    positions = [
        [case_offset_x + m25_inset_x,                    case_offset_y + m25_inset_y],
        [case_offset_x + m25_inset_x + m25_spacing_x,    case_offset_y + m25_inset_y],
        [case_offset_x + m25_inset_x,                    case_offset_y + m25_inset_y + m25_spacing_y],
        [case_offset_x + m25_inset_x + m25_spacing_x,    case_offset_y + m25_inset_y + m25_spacing_y],
    ];
    for (pos = positions) {
        translate([pos[0], pos[1], 0])
            children();
    }
}

module standoffs() {
    standoff_positions() {
        difference() {
            cylinder(h=standoff_h, r=standoff_r, $fn=20);
            translate([0, 0, -1])
                cylinder(h=standoff_h + 2, r=m25_hole_r, $fn=16);
        }
    }
}

module standoff_bottom_holes() {
    // Through-holes in bottom panel for M2.5 screws
    standoff_positions() {
        translate([0, 0, -1])
            cylinder(h=wall + 2, r=m25_hole_r, $fn=16);
    }
}

module magnet_positions_body() {
    // Magnet recesses on top edge of body walls
    positions = [
        [wall + magnet_inset,                wall + magnet_inset],
        [outer_width - wall - magnet_inset,  wall + magnet_inset],
        [wall + magnet_inset,                outer_depth - wall - magnet_inset],
        [outer_width - wall - magnet_inset,  outer_depth - wall - magnet_inset],
    ];
    for (pos = positions) {
        translate([pos[0], pos[1], 0])
            children();
    }
}

module magnet_recesses_body() {
    magnet_positions_body() {
        translate([0, 0, inner_height + wall - magnet_depth])
            cylinder(h=magnet_depth + 1, r=magnet_r, $fn=20);
    }
}

module magnet_recesses_lid() {
    magnet_positions_body() {
        translate([0, 0, -1])
            cylinder(h=magnet_depth + 1, r=magnet_r, $fn=20);
    }
}

module mirror_tab() {
    // Small support tab for half mirror (glued at 45 degrees to side wall)
    tab_w = 15;
    tab_d = 10;
    tab_h = 10;

    // Triangular cross-section: 45-degree shelf
    hull() {
        cube([tab_w, tab_d, 0.1]);
        cube([tab_w, 0.1, tab_h]);
    }
}

// ============================================================
// Main body (open-top box)
// ============================================================

module body() {
    difference() {
        // Outer shell
        rounded_box(outer_width, outer_depth, inner_height + wall, r=2);

        // Inner cavity
        translate([wall, wall, wall])
            cube([inner_width, inner_depth, inner_height + 1]);

        // Front viewing window
        viewing_window();

        // Back ventilation
        translate([0, outer_depth - wall - 0.5, 0])
            vent_slots();

        // Back cable hole
        translate([0, outer_depth - wall - 0.5, 0])
            cable_hole();

        // Bottom M2.5 through-holes
        standoff_bottom_holes();

        // Magnet recesses on top edge
        magnet_recesses_body();
    }

    // Internal: M2.5 standoffs
    translate([0, 0, wall])
        standoffs();
}

// ============================================================
// Lid (top panel, magnet-attached)
// ============================================================

module lid() {
    lip_w = 1.5;
    lip_h = 3;

    difference() {
        union() {
            // Main plate
            rounded_box(outer_width, outer_depth, wall, r=2);
            // Inner alignment lip
            translate([wall + 0.3, wall + 0.3, wall])
                cube([inner_width - 0.6, inner_depth - 0.6, lip_h]);
        }

        // Hollow out the lip (make it a frame)
        translate([wall + lip_w + 0.3, wall + lip_w + 0.3, wall - 1])
            cube([inner_width - lip_w*2 - 0.6, inner_depth - lip_w*2 - 0.6, lip_h + 2]);

        // Magnet recesses (on underside)
        magnet_recesses_lid();
    }
}

// ============================================================
// Rendering
// ============================================================

if (RENDER_PART == "preview") {
    // Full assembly preview
    color("#222") body();
    color("#333", 0.6) translate([0, 0, inner_height + wall + 0.5]) lid();

    // Mirror support tabs (4 total: 2 per side, front and back)
    color("#555") {
        // Left side - front tab
        translate([wall, wall + 15, wall + mirror_start_z])
            rotate([0, 0, 0])
                mirror_tab();
        // Left side - back tab
        translate([wall, outer_depth - wall - 25, wall + mirror_start_z])
            mirror_tab();
        // Right side - front tab
        translate([outer_width - wall, wall + 15, wall + mirror_start_z])
            mirror([1, 0, 0])
                mirror_tab();
        // Right side - back tab
        translate([outer_width - wall, outer_depth - wall - 25, wall + mirror_start_z])
            mirror([1, 0, 0])
                mirror_tab();
    }

    // Half mirror (visualization)
    color("#88ccff", 0.25)
        translate([wall + 1, wall + 10, wall + mirror_start_z])
            rotate([45, 0, 0])
                cube([inner_width - 2, 200, mirror_thickness]);

    // Display unit - back plate (visualization)
    color("#1a1a2e", 0.4)
        translate([
            case_offset_x,
            case_offset_y,
            wall + standoff_h
        ])
            cube([case_width, case_depth, case_base_h]);

    // Display unit - Pi bump (visualization)
    color("#2a2a3e", 0.4)
        translate([
            (outer_width - pi_bump_w) / 2,
            (outer_depth - pi_bump_d) / 2,
            wall
        ])
            cube([pi_bump_w, pi_bump_d, standoff_h]);

    // Display face (top, visualization)
    color("#000", 0.6)
        translate([
            case_offset_x,
            case_offset_y,
            wall + standoff_h + case_total_h - 1
        ])
            cube([case_width, case_depth, 1]);

} else if (RENDER_PART == "body") {
    body();

} else if (RENDER_PART == "lid") {
    // Print with outer face down
    lid();

} else if (RENDER_PART == "mirror_tab") {
    // Print 4 copies of this
    mirror_tab();
}
