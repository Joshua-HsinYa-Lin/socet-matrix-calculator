# FPGA Matrix Calculator User Guide

This document outlines the user interface and operational flow for the hardware-based Matrix Calculator, designed for an FPGA simulator (such as ECE270). The system supports up to 9x9 matrix addition, multiplication, and transposition using a 4x5 keypad, 7-segment displays, and indicator LEDs.

## 1. Hardware Interface Overview

* **Display:** 8-digit 7-segment display (Top) for alphanumeric prompts and numeric values.
* **LEDs:** * 8 Left LEDs: Indicates row input progress or current row index.
    * 8 Right LEDs: Indicates column input progress or current column index.
    * 1 Middle LED: System status indicator (Error, Ready, Processing).
* **Keypad:** 20 keys (0-9, A-F, W-Z) for data entry, navigation, and control.

## 2. Keypad Mapping & Controls

| Key | Function in Input Mode | Function in Output Mode |
| :--- | :--- | :--- |
| **0-9** | Numeric data entry | Numeric data entry (for specific index search) |
| **Z** | Shift digit left (during element input) | - |
| **Y** | Confirm/Enter (Write to memory) | Confirm/Enter |
| **X** | **Long Press:** System Reset / Abort | **Long Press:** System Reset / Exit Output |
| **A** | Select Operation: Addition | Navigate: Left Element |
| **B** | Select Operation: Multiplication | Navigate: Down Element |
| **C** | Select Operation: Transposition | - |
| **D** | - | Navigate: Right Element |
| **W** | - | Navigate: Up Element |
| **F** | - | Specify Mode: Jump to Row/Col index |

## 3. Operational Flow

### Step 1: Initialization & Matrix 1 Dimensions
1. On startup, the display prompts `ROW`.
2. Enter the row size (1-9). Press **Y** to confirm.
3. The display prompts `COL`. Enter the column size (1-9) and press **Y**.
4. The middle LED turns solid ON. *(Note: Invalid dimensions will cause the middle LED to blink slowly).*

### Step 2: Entering Matrix 1 Elements
1. The display prompts the current coordinate being entered (e.g., `ROW1COL1`).
2. Input up to 3 digits for the element value. 
    * Press a number, then press **Z** to shift it left.
    * Example for "125": Press `1` -> `Z` -> `2` -> `Z` -> `5`.
3. Press **Y** to store the value in memory and advance to the next coordinate.
4. Input proceeds row by row, left to right.
5. **LED Indicators:** The Left 8 LEDs show row progress; the Right 8 LEDs show column progress (No lights = 1, all 8 lights = completed).
6. Once Matrix 1 is completely entered, the middle LED switches to a **fast blink**.

### Step 3: Operation Selection
1. With the middle LED fast blinking, select the operation:
    * Press **A** for Addition.
    * Press **B** for Multiplication.
    * Press **C** for Transposition.
2. Press **Y** to confirm.

### Step 4: Entering Matrix 2 (If Applicable)
Depending on the chosen operation, the system will prompt for Matrix 2 parameters:
* **Addition:** The dimensions are fixed to match Matrix 1. The system immediately prompts for Matrix 2 elements (`ROW1COL1`). Follow the Step 2 procedure.
* **Multiplication:** The Matrix 2 row size is fixed to match Matrix 1's column size. The display will prompt `COL` for Matrix 2's column size. Enter it, press **Y**, then enter elements following Step 2.
* **Transposition:** No second matrix is required. The system immediately advances to computation.

### Step 5: Processing Calculation
1. The Left and Right LEDs will blink in sequence.
2. The display will show the operation code (`ADD`, `MUL`, `TRA`) for a minimum of 1 second.

### Step 6: Viewing Outputs
1. **Default View:** Displays the element at Row 1, Col 1. The Left and Right LEDs show the current 0-based Row and Column indices.
2. **Navigation:** Use **W** (Up), **B** (Down), **A** (Left), and **D** (Right) to pan through the result matrix. Attempting to navigate out of bounds will be ignored.
3. **Specify Mode:** Press **F**, enter the target row index, press **Y**, enter the target column index, press **Y**. The display will jump to that specific element.
4. Long-press **X** at any time to reset the calculator for a new operation.
