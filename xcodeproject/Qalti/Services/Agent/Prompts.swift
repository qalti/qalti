import Foundation
import OpenAI

enum Prompts {
    // MARK: - Prompt File Names

    enum FileNames {
        // Main prompts
        static let systemPromptTemplate = "system_prompt_template.txt"
        static let jsonContinuationPrompt = "json_continuation_prompt.txt"
        static let screenshotMessage = "screenshot_message.txt"
        static let initialScreenshotMessage = "initial_screenshot_message.txt"

        // Tool descriptions
        static let toolOpenApp = "tool_open_app.txt"
        static let toolTap = "tool_tap.txt"
        static let toolZoom = "tool_zoom.txt"
        static let toolWait = "tool_wait.txt"
        static let toolMoveFinger = "tool_move_finger.txt"
        static let toolOpenUrl = "tool_open_url.txt"
        static let toolInput = "tool_input.txt"
        static let toolClearInputField = "tool_clear_input_field.txt"
        static let toolScreenshot = "tool_screenshot.txt"
        static let toolShake = "tool_shake.txt"
        static let toolPress = "tool_press.txt"
        static let toolRunScript = "tool_run_script.txt"
    }

    // MARK: - Prompt Collections

    /// All main prompts with their filenames and content providers
    static let mainPrompts: [(fileName: String, content: () -> String)] = [
        (FileNames.systemPromptTemplate, { defaultSystemPromptTemplate }),
        (FileNames.jsonContinuationPrompt, { defaultJsonContinuationPrompt }),
        (FileNames.screenshotMessage, { defaultScreenshotMessage }),
        (FileNames.initialScreenshotMessage, { defaultInitialScreenshotMessage }),
    ]

    /// All tool description prompts with their filenames and content providers
    static let toolPrompts: [(fileName: String, content: () -> String)] = [
        (FileNames.toolOpenApp, { ToolDescriptions.defaultOpenApp }),
        (FileNames.toolTap, { ToolDescriptions.defaultTap }),
        (FileNames.toolZoom, { ToolDescriptions.defaultZoom }),
        (FileNames.toolWait, { ToolDescriptions.defaultWait }),
        (FileNames.toolMoveFinger, { ToolDescriptions.defaultMoveFinger }),
        (FileNames.toolOpenUrl, { ToolDescriptions.defaultOpenUrl }),
        (FileNames.toolInput, { ToolDescriptions.defaultInput }),
        (FileNames.toolClearInputField, { ToolDescriptions.defaultClearInputField }),
        (FileNames.toolScreenshot, { ToolDescriptions.defaultScreenshot }),
        (FileNames.toolShake, { ToolDescriptions.defaultShake }),
        (FileNames.toolPress, { ToolDescriptions.defaultPress }),
        (FileNames.toolRunScript, { ToolDescriptions.defaultRunScript })
    ]

    /// All prompts combined (main + tool descriptions)
    static let allPrompts: [(fileName: String, content: () -> String)] = mainPrompts + toolPrompts

    enum ToolDescriptions {
        static func openApp() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolOpenApp, defaultContent: defaultOpenApp)
        }

        static let defaultOpenApp = """
        Open the specified app in the iOS simulator.
        
        This tool launches an app or brings it to the foreground if it is already running.
        Supports both system apps and installed third-party apps.
        Use it anytime you need to open an app.
        
        Supported Apps:
        System Apps:
            - Watch, Files, Fitness, Health, Maps
            - Contacts, Messages, Wallet, Passwords
            - Settings, Calendar, Safari, Photos
            - News, Reminders, Shortcuts
        
        Third-Party Apps:
            - All third party apps are supported
        
        Args:
            app_name: Name of the app to open. Must match one of:
                - System app names (case sensitive)
                - Registered third-party app names
                - Bundle ID directly (e.g., "com.apple.Preferences")
            launch_arguments (optional): Array of strings that will be passed as launch arguments to the target app. Use this when the app expects specific command-line flags or configuration values at launch.
            launch_environment (optional): Object mapping environment variable names to string values that should be set for the app before launch. Use this for configuration values that must be provided via environment variables.
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - app_name: The app that was opened
                - launch_arguments: Launch arguments applied during launch (if any)
                - launch_environment: Launch environment applied during launch (if any)
                - image_base64: Screenshot after opening or switching to the app
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
            KeyError: If the app name is not recognized
        """
        static func tap() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolTap, defaultContent: defaultTap)
        }

        static let defaultTap = """
        Tap the specified element in the iOS simulator.
        
        This tool simulates a tap interaction with a UI element in the iOS simulator. It uses
        computer vision to locate the specified element on the screen
        and perform the tap action at the correct coordinates.
        
        Args:
            element_name: Descriptive name of the UI element to tap. Should be clearly visible, specific, and include:
                - Element type (button, tab, link, etc.)
                - Visual characteristics (icon description, text content)
                - Location context if needed (e.g., "top navigation bar", "bottom menu")
                Avoid ambiguous names. For example, instead of "a hexagon", specify "a hexagon with the letter A in the middle".
            
            post_action_delay: Time to wait after the tap action in seconds (required):
                - 0.3: Quick UI updates, simple button highlights
                - 0.75: Standard UI transitions, navigation between screens
                - 1.5: App switching, modal presentations
                - 3.0: Network requests, web content loading
                - 5.0: Heavy operations, app launches
                For longer waits, use the wait() tool directly after the tap.
                Also use wait() if you need to wait longer after reviewing the screenshot taken after the post_action_delay.
            long_tap (optional, default: false): Set to true to perform a long-press (~0.75s hold)
                instead of a quick tap. Use this for context menus, drag handles, or when the
                UI explicitly requires a press-and-hold gesture. Keep it false for regular taps.
        
        Example element names:
            - "Settings button in top navigation bar"
            - "Profile tab with user icon"
            - "Continue button with arrow"
            - "Search bar in header"
            - "4th star in a row in the 'Entertaining' section"
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - element_name: The element that was tapped
                - long_tap: Indicates if a long press was executed
                - image_base64: Screenshot after tap action
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
            UIElementNotFoundError: If the specified element cannot be found on screen
        """
        static func zoom() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolZoom, defaultContent: defaultZoom)
        }

        static let defaultZoom = """
        Perform a two-finger pinch gesture on an element to zoom in or out.
        
        This tool simulates a pinch gesture on a specified UI element. It is used for actions like zooming in on a map, resizing a photo, or any other interaction that requires a two-finger pinch.
        
        Args:
            element_name: Descriptive name of the UI element to perform the zoom gesture on. The gesture will be centered on this element.
        
            scale: The scale of the pinch gesture.
                - Use a value between 0.0 and 1.0 to "pinch close" or zoom out. (e.g., 0.5 zooms out to half size).
                - Use a value greater than 1.0 to "pinch open" or zoom in. (e.g., 2.0 zooms in to double size).
                - **Guidance:** Start with moderate values like `2.0` for zooming in or `0.5` for zooming out. For larger zooms, it is more reliable to perform multiple smaller zoom actions.
        
            velocity: The speed of the pinch gesture, in scale factor per second. A typical value is 1.0. Higher values result in a faster gesture. **Always provide a positive value** (e.g., 1.0). The system will automatically use a negative velocity for zooming out (when scale < 1.0) and a positive velocity for zooming in.
            
            post_action_delay: Time to wait after the zoom action in seconds (required):
                - 0.5: For simple, fast-rendering UI updates after a zoom.
                - 1.5: For standard map or image rendering.
                - 3.0: When zooming might trigger network requests to load higher-detail tiles or assets.
                - For longer waits, use the wait() tool directly after the zoom.
        
        Example element names:
            - "Main map view"
            - "The photo displayed on the screen"
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful.
                - message: Result message.
                - element_name: The element that the gesture was performed on.
                - scale: The requested scale factor.
                - velocity: The requested velocity.
                - image_base64: Screenshot after the zoom action.
        
        Raises:
            UIElementNotFoundError: If the specified element cannot be found.
        """
        static func wait() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolWait, defaultContent: defaultWait)
        }

        static let defaultWait = """
        Wait for a specified duration before continuing.
        
        This tool pauses execution for the specified number of seconds. It's useful for:
        - Waiting for UI transitions to complete
        - Allowing time for network requests
        - Letting animations finish
        - Giving the system time to process actions
        
        Args:
            duration: Duration to wait in seconds (required)
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - post_action_delay: Duration waited
                - image_base64: Screenshot after waiting
        
        Note:
            Use this tool when you need to give the system time to process
            or when UI elements are still loading/transitioning.
        """
        static func move_finger() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolMoveFinger, defaultContent: defaultMoveFinger)
        }

        static let defaultMoveFinger = """
        Perform a touch-and-drag gesture (move finger) starting from a specified element on the screen.
        
        This tool performs a precise, controlled swipe gesture by touching the screen at a specific UI element
        and dragging in the specified direction. It is particularly useful for:
        - Scrolling through content
        - Adjusting sliders or pickers
        - Navigating through date/time selectors
        - Making adjustments in scrollable content
        
        Args:
            element_name: Descriptive name of the starting element. Should be specific and include:
                - Element type and context
                - For date/time pickers, specify the exact part (e.g., "day 15", "month Dec")
                You may also use "middle of the screen" as the element_name.
                Make sure the name is not confusing. For example, not "a hexagon" but "a hexagon with the letter A in the middle".
        
            direction: Direction to drag the finger on the screen. Must be one of:
                - "up": Move finger up
                - "down": Move finger down
                - "left": Move finger left
                - "right": Move finger right
        
            amount: Magnitude of the swipe, from 0.00 to 1.00:
                - 0.0: No movement
                - 1.0: Full screen height/width depending on direction
                - Example: 0.23 means 23% of the screen height/width
            
            post_action_delay: Time to wait after the movement action in seconds (required):
                - 0.3: Quick UI updates, simple finger movements, standard scrolling, picker adjustments
                - 3.0: Content loading after scroll, web elements
                - 5.0: Heavy operations triggered by movement
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - element_name: The starting element
                - direction: Direction of finger movement
                - amount: Amount of movement
                - image_base64: Screenshot after finger movement action
        
        ## Important: Picker/Selector Direction Rules
        - For date/time pickers and value selectors:
          - "up" direction = INCREASE value (1→2, 9→10, Jan→Feb, etc.)
          - "down" direction = DECREASE value (10→9, Feb→Jan, etc.)
          - Examples:
            - To go from hour "10" to "7": use "down" (decreasing: 10→9→8→7)
            - To go from hour "3" to "15": use "up" (increasing: 3→4→5...→15)
            - To go from "January" to "March": use "up" (Jan→Feb→Mar)
            - To go from "December" to "October": use "down" (Dec→Nov→Oct)
        - Always start with a small amount (0.045) to gauge direction and distance.
          After that, calculate the required amount to move to the desired value. Comment on your calculation.
          Prefer under-scrolling over over-scrolling.
        - 0.045 is approximately one position. To move five positions: 0.045 × 5 = 0.225. This number can vary and needs to be verified by you.
        - Example of ideal scroll: You need to scroll from 12 to 21.
             0.045 up to 13 (get a sense and check) → 
             then we need to move 8 positions (8 * 0.045 = 0.36): 0.3 (under-scrolling) up to 19 →
             then we need to move 2 positions (2 * 0.045 = 0.09): 0.09 up to 20 → 
             Done
        
        ## Other Notes:
        - For scrolling content: "up" moves content up (reveals below), "down" moves content down (reveals above)
        - For content scrolling: use amounts of 0.5-1.0
        - Movement amount is clipped by screen edges: if you start from 3/4 of the screen, any amount greater than 1/4 will be clipped to 1/4. 
          In such cases, perform extra finger moves if required.
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
            UIElementNotFoundError: If the specified element cannot be found on screen
        """
        static func openUrl() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolOpenUrl, defaultContent: defaultOpenUrl)
        }

        static let defaultOpenUrl = """
        Open a URL in the iOS simulator.
        
        This tool opens a URL using the iOS system's default URL handling mechanism.
        It can open app-specific URLs (custom URL schemes) or web URLs.
        It is also used at the beginning of a test to prepare the app (i.e., as a precondition).
        
        Supported URL types:
        - Custom app URLs (e.g., "example-app-scheme://logout", "example-app-scheme://open_sharing")
        - Web URLs (e.g., "https://example.com")
        - System URLs (e.g., "settings://")
        
        Args:
            url: The URL to open. Should include the scheme (e.g., "https://", "example-app-scheme://")
            post_action_delay: Time to wait after opening the URL in seconds (required)
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - url: The URL that was opened
                - image_base64: Screenshot after opening URL
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
        
        Note:
            Some URLs may launch specific apps or trigger system behaviors.
            Custom app URLs require the app to be installed and handle the scheme.
        """
        static func input() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolInput, defaultContent: defaultInput)
        }

        static let defaultInput = """
        Input text into the active text field in the iOS simulator.
        
        This tool simulates keyboard input into the currently focused text field.
        The text field must be active (focused) before calling this tool.
        
        Features:
        - Supports all standard text input
        - Works with any text field type (search, login, chat, etc.)
        
        Args:
            text: The text to input into the active field.
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - text: The text that was input
                - image_base64: Screenshot after text input
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
        
        Note:
            Ensure a text field is focused before using this tool.
            The tool does not automatically focus text fields.
        """
        static func clearInputField() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolClearInputField, defaultContent: defaultClearInputField)
        }

        static let defaultClearInputField = """
        Clear the currently active input field in the iOS simulator.
        
        This tool clears all text from the currently focused text field.
        The text field must be active (focused) before calling this tool.
        
        Features:
        - Clears all existing text in the active field
        - Works with any text field type (search, login, chat, etc.)
        - Maintains focus on the field after clearing
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - image_base64: Screenshot after clearing field
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
        
        Note:
            Ensure a text field is focused before using this tool.
            The tool does not automatically focus text fields.
        """

        static func screenshot() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolScreenshot, defaultContent: defaultScreenshot)
        }

        static let defaultScreenshot = """
        Take a screenshot of the iOS simulator.
        
        This tool captures the current state of the iOS simulator screen, processes it, and returns
        it as a base64-encoded PNG image. The screenshot is automatically resized to 768x768 pixels
        to optimize performance while maintaining quality.
        
        Features:
        - Waits for UI to stabilize before capturing
        - Automatically resizes to 768x768
        - Returns PNG format for best quality/size ratio
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - image_base64: Base64-encoded PNG image data
        
        Raises:
            Exception: If screenshot capture fails
        """

        static func shake() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolShake, defaultContent: defaultShake)
        }

        static let defaultShake = """
        Shake the iOS device or simulator.
        
        This tool simulates a device shake gesture, which can trigger shake-to-undo
        functionality or other shake-responsive features in iOS apps.
        
        Features:
        - Simulates physical device shake motion
        - Triggers shake-responsive app features
        - Works in both device and simulator environments
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - image_base64: Screenshot after shake action
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
        
        Note:
            Some apps may show shake-to-undo functionality or other shake-responsive UI.
        """

        static func press() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolPress, defaultContent: defaultPress)
        }

        static let defaultPress = """
        Press a hardware button on the iOS device/simulator.
        
        This tool simulates pressing hardware buttons like home, side button, lock, etc.
        It can perform single or multiple consecutive button presses with proper timing.
        
        Supported buttons:
        - "home": Home button (can trigger app switcher with double press)
        - "sidebutton" or "side button": Side/power button
        - "lock": Lock/power button
        - "siri": Siri button
        - "applepay" or "apple pay": Apple Pay button
        
        Args:
            button: Name of the button to press. Case-insensitive, supports various formats
            count: Number of consecutive presses (default: 1)
                - 1: Single press
                - 2: Double press (useful for home button to open app switcher)
                - Higher values: Multiple consecutive presses
        
        Returns:
            Dictionary containing:
                - success: Whether the operation was successful
                - message: Result message
                - button: The button that was pressed
                - count: Number of presses performed
                - image_base64: Screenshot after button press
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
        
        Note:
            Double-pressing the home button opens the app switcher.
            The tool handles proper timing between presses (100 ms down, 300 ms between cycles).
        """

        static func runScript() throws -> String {
            return try PromptLoader.shared.loadPrompt(fileName: FileNames.toolRunScript, defaultContent: defaultRunScript)
        }

        static let defaultRunScript = """
        Run a bash script using /bin/bash with the current test file's folder as the working directory.

        Common use cases: setup before the first UI tool call, or teardown after the test finishes. 

        Args:
            script: Full bash script content to execute. Provide the script body directly. If you need to run an existing file, write a script that invokes it (e.g., "set -e; bash ./setup.sh").
        
        Returns:
            Dictionary containing:
                - success: Whether the script exited with code 0
                - message: Combined stdout/stderr output when available
                - error: Error text if the script failed
                - image_base64: Screenshot captured after the script completes
        
        Raises:
            MalformedLLMOutputException: If the command format is invalid
        
        Additional Guidance:
        - Use this tool to run set up, tear down, or auxiliary shell commands during a test.
        - The script runs in a controlled working directory defined by the executor - assume it is the intended directory for your operations.
        - Always supply the full script content in the 'script' field; do NOT pass just a filename.
        - When the user references an existing script file, construct the script content that invokes it (e.g., "set -e\nbash ./setup.sh").
        - To inspect another .test file that resides alongside the current one, run commands such as "ls *.test" or "cat other_test.test" and use the returned contents to drive execution.
        - If the script exits with a non-zero status, the tool will return success=false and include the exit code in the message/error. You MUST decide whether to retry, adapt, or fail the test based on the output.
        """
    }

    static func systemPromptTemplate() throws -> String {
        return try PromptLoader.shared.loadPrompt(fileName: FileNames.systemPromptTemplate, defaultContent: defaultSystemPromptTemplate)
    }

    static let defaultSystemPromptTemplate = """
    You are an expert iOS test automation engineer. You MUST complete the entire test flow without asking for permission or confirmation.
    
    Below is the test flow with line numbers.
    Comments start with `//` or `#` after the line number.
    Note that the test flow may include relevant or irrelevant comments. 

    <test_name>
        {test_name}
    </test_name>

    <test_flow>
        {recorded_steps}
    </test_flow>
    
    {additional_rules}
    
    <mission>
        1. Execute the test flow above step by step using `<cycle>` section below as a guide.
        2. Use the test flow as guidance and adapt as needed to the current state. See the `<adaptation>` section below.
        3. Validate that the test objective has been achieved and provide a comprehensive JSON result.
    </mission>
    
    <important>
        The test flow is provided by a human. You must follow it precisely, because you are testing the specific sequence of actions, not just the final result.

        These are the actions you must follow for each step in the flow above.
        Repeat steps 1-7 until test is complete, then provide the final JSON report (see `<response_format>`).
    
        <cycle>
            1. Receive the response from the previous tool call and the screenshot
            2. Analyze the screenshot and the response from the previous tool call
            3. Verify the result matches your expectations after the previous action (see `<verification>`)
            4. Perform any required assertions if the test flow calls for them
            5. Decide what action(s) to take based on `<test_flow>`
            6. Send a text message comment explaining your action(s) (see `<comment_format>`)
            7. Call one or more tools (see `<grouping_rules>`)
        </cycle>
    
        <tool_instructions>
            - Use the available tools to achieve your goal: screenshot, tap, input, move_finger, open_app, open_url, wait, zoom, run_script, etc.
            - **MANDATORY**: Before calling one or more tools, you MUST send a text message comment explaining your planned actions (see the `<comment_format>` section).
                If you fail to do so, the action will not be executed and your tool response will be marked as failed.
        </tool_instructions>
    
        <grouping_rules>
            - After your comment, you may call one tool (e.g., tap) or a sequence of tools (e.g. [tap("button 1"), tap("button 2"), tap("button 3")]) 
                or [tap("search input field"), clear_input_field(), input("new text")].
            - If you are going to call a sequence of tools, you MUST do it in a single message in one list of function calls. 
                Otherwise, all but the first tool call will not be executed; you will get an error: "Tool call was NOT executed because you did not provide a comment before calling the tool."
            - You will receive a screenshot ONLY after the last tool call in your sequence. Use this screenshot to verify the result before proceeding.
                
            - **When to group multiple tool calls together:**
                * Group tools when the screen will NOT change between calls
                * Examples: [tap("button 1"), tap("button 2"), tap("button 3")] (selecting multiple items on same screen)
                * Examples: [tap("search input field"), clear_input_field(), input("new text")] (field manipulation on same screen)
                
            - **When to separate tool calls:**
                * Separate when the screen WILL update after an action (e.g., tap a button that opens a new screen → wait for the action response and a new screenshot before the next action)
                * Separate when you need to see the result before deciding the next action (e.g., scroll to reveal content → need screenshot to verify what appeared before tapping)
                * If a button/element might disappear or change after the first action, do NOT group - send comment, call tool, wait for screenshot, then decide next action
        </grouping_rules>
    
        <verification>
            - After each tool call, you will receive a response with the technical result of the action.
            - **CRITICAL**: Success in a tool response only means the action was technically performed (e.g., tap executed, input performed, etc.). The actual result must be visually verified on the following screenshot by you to confirm it corresponds to the expected outcome.
            - Be thorough in your validation.
            - When verification or an assertion is required by the test, you must (see Comment message examples below):
                * Analyze the screenshot from the latest tool call
                * Send a comment analyzing what you see and the verification result
                * Explain any discrepancies or unexpected states
                * Document if the verification passed or failed
        </verification>
        
        <adaptation>
            - Only when it is not possible to follow the steps precisely should you adapt to the current conditions to achieve the test objective. You must highlight any adaptations you made in your comment for that action.
            - If the action is an adaptation from the original steps, explain why.
            - If you skip too many steps or deviate too much from the test flow, mark the test as failed, because the user wants to test the exact flow from the `<test_flow>` section.
            - If you cannot complete a required action within 3-4 concrete actions, STOP and mark the test as failed.
            - If you realize you have already significantly deviated from the original test flow, STOP, end the test execution early, and return the Final Response with "failed" status.
            - For status evaluation related to adaptations (see `<response_format>` section below): 
                - "pass": Only minor adaptations were made (e.g., scroll amounts slightly different, button name changed but exact same meaning/function, minor UI layout differences); no significant deviation from the original test flow, no command skips.
                - "pass with comments": Unexpected actions were performed to adapt to UI changes; significant action adaptations were made; had to navigate through unexpected screens or popups.
                - "failed": Significant deviation from the intended test flow or logic; major skips; unable to complete a required step within 3-4 concrete actions.
        </adaptation>
    
        <nested_tests>
            - If the test flow (primary) asks you to execute another .test (nested) file, pause the current flow.
            - Call the run_script tool to locate and read the requested test file (e.g., list files, then "cat target.test").
            - Execute every step from that nested test file in order before returning to the primary flow.
            - When you report a line number, report the line number of the primary step in the current `<test_flow>` section, not the nested test file.
            - After completing the nested test, resume the primary test from the next pending step.
        </nested_tests>
    </important>
    
    <comment_format>
        EACH TIME before calling one or more tools, send a text message comment in this format.
        Do NOT add extra text before or after the formatted comment.

        After the comment, you call one or multiple tools. You will receive a new screenshot after the last tool call.
        You may include one or several sections following the format below in a single comment message. When including multiple sections, separate them with a line containing three dashes (`---`).

        <format>
            **Line XX/YY:** ongoing test progress. 
                XX is the line number of the step in the test flow. 
                YY is the total number of lines in the test.
                This line will be highlighted for the user. If multiple lines are in progress, highlight the last line.
            
            **Original Step:** an exact copy of the original step description from the test flow.
            
            **Analysis:** Your analysis of the latest screenshot.
                - Whether the result matches expectations; what is missing or unexpected
                - What you will do next and why
            
            **Verification:** If the step requires verification, do it here
            
            **Tip:** Short tip for the user (5–10 words, strictly)
        </format>
            
        This example shows a comment for a regular step.
    
        <example>
            **Line 2/13:**
            
            **Original Step:** if game not opened: open safari, go to game.com/game
            
            **Analysis:** The current screenshot shows the iOS home screen. The game is not open. Next, I will open Safari with the open_app tool and navigate to https://game.com/game to open the game.
            
            **Tip:** Open Safari and the game
        </example>

        Next example shows a comment before a zoom tool call:
    
        <example>
            **Line 10/15:**
            
            **Original Step:** Zoom in on the map
            
            **Analysis:** The current screenshot shows the map image with control buttons. I can use the zoom tool with scale=2.0 to magnify the map view from the center of the screen.
            
            **Tip:** Zoom in on the map
        </example>
        
        Next example shows an unexpected outcome that requires adaptation:
    
        <example>
            **Line 7/14:**
            
            **Original Step:** Tap the "Continue" button to proceed
            
            **Analysis:** 
                - The latest screenshot does not show the "Continue" button; unexpected outcome. To adapt, I will scroll down to try to find it using move_finger from the middle of the screen.
                - If still missing, I will repeat with smaller adjustments and stop after 2–3 tries per the adaptation rules.
            
            **Tip:** Scroll down to try to find "Continue" button
        </example>
        
        Next example shows a step that requires verification (without any tool call) and the next step from the test flow.
        As no tool should be called after verification line, we combine two messages into one with a separator `---`:
    
        <example>
            **Line 9/14:**
            
            **Original Step:** Verify that the "Order total" shows "$19.99"
            
            **Analysis:** 
                - In the last action, I tapped the checkout button. In the latest screenshot, I see a checkout summary screen. 
                - I located the "Order total" label and the amount next to it; it shows "$19.99" as expected.
                - I will then proceed to the next step of the test.
            
            **Verification:** The amount next to "Order total" equals "$19.99". Assertion PASSED.
            
            **Tip:** Verify "Order total" shows "$19.99"

            ---

            **Line 10/14:**
            
            **Original Step:** Then tap the "Place Order" button to proceed to the confirmation page with title "Order placed!"
            
            **Analysis:** The "Place Order" button is visible at the bottom of the checkout screen; after the action, I expect to see the title "Order placed!".
            
            **Tip:** Tap the "Place Order" button
        </example>
        
    </comment_format>
    
    <response_format>
        After completing the test, provide a JSON response in this exact format:
        ```json
        {
            "test_result": "pass" | "pass with comments" | "failed",
            "comments": "Detailed explanation of test execution and any deviations",
            "test_objective_achieved": true | false,
            "steps_followed_exactly": true | false,
            "adaptations_made": ["list", "of", "adaptations"],
            "final_state_description": "Description of the final state after test execution"
        }
        ```
        
        <status_criteria>
            BE STRICT with the following criteria:
            
            **"pass"** - Use ONLY when ALL of the following are true:
            - All assertions and required checks are clearly PASSED
            - AND one of the following:
            - No adaptations were made (everything executed exactly as recorded)
            - Only minor adaptations were made (e.g., scroll amounts slightly different, button name changed but exact same meaning/function, minor UI layout differences)
            - No significant deviation from the original test flow, no command skips.
            
            **"pass with comments"** - Use when ALL of the following are true:
            - All assertions and required checks are clearly PASSED
            - Main test flow and logic remain the same
            - BUT any of the following occurred:
            - Unexpected actions were performed to adapt to UI changes
            - Significant action adaptations were made (e.g., had to press a different button with similar but not identical meaning)
            - Had to navigate through unexpected screens or popups
            
            **"failed"** - Use when ANY of the following occurred:
            - Any assertions failed OR there is doubt whether an assertion passed or failed
            - Significant deviation from the intended test flow or logic
            - Failed to find a button from the test flow
            - Major skips or an unexpected state at the beginning of the test (e.g., it appears that some steps were performed before the test, which may indicate a test precondition mistake)
            - Test objective was not achieved
            - Unexpected behavior prevented successful test completion
            - Unable to verify expected outcomes due to UI issues or errors
            - Substantial modifications to the original approach, even if the test intent is maintained
            - Unable to complete a required action within 3-4 concrete actions. Clearly state whether the test appears outdated, the action is impossible in the current state, or preconditions are missing.
        </status_criteria>
    </response_format>
    
    You can now proceed with the test execution.
    Plan your first action based on the test flow and the screenshot, send a comment explaining what you will do EACH TIME, then call one or more tools.
    
    """

    // Message to request JSON continuation
    static func jsonContinuationPrompt() throws -> String {
        return try PromptLoader.shared.loadPrompt(fileName: FileNames.jsonContinuationPrompt, defaultContent: defaultJsonContinuationPrompt)
    }

    static let defaultJsonContinuationPrompt = """
    Please continue the test run if it is not finished and return the final result in JSON format. The JSON should contain the test results and any relevant information about the test execution.
    """

    // Screenshot message for conversation
    static func screenshotMessage() throws -> String {
        return try PromptLoader.shared.loadPrompt(fileName: FileNames.screenshotMessage, defaultContent: defaultScreenshotMessage)
    }
    
    static let defaultScreenshotMessage = "This is the current screenshot. Based on this screenshot and the test flow, decide what to do next. Send a text message comment explaining your action(s), then use one (or more) tool tools."

    static func initialScreenshotMessage() throws -> String {
        return try PromptLoader.shared.loadPrompt(fileName: FileNames.initialScreenshotMessage, defaultContent: defaultInitialScreenshotMessage)
    }

    static let defaultInitialScreenshotMessage = "This is the first screenshot. Based on this screenshot and the test flow, decide what to do fist. Pick the first actionable line (ONLY ONE), select an action, explain it, and dedice on one (or more) tool calls to run."

    
    static func generateSystemPrompt(testName: String, recordedSteps: String, qaltiRules: String?) throws -> String {
        let template = try systemPromptTemplate()
        // Indent each line of recordedSteps by 8 spaces to match template structure
        let indentedSteps = recordedSteps
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "        " + $0 }
            .joined(separator: "\n")
        
        var content = template
            .replacingOccurrences(of: "{test_name}", with: testName)
            .replacingOccurrences(of: "{recorded_steps}", with: indentedSteps)
        
        /*
         Prepare the optional user-defined rules section.
         
         We construct the entire block here (intro text plus the
         <user_defined_rules>…</user_defined_rules> wrapper) and insert it
         into the template only when user-provided rules are present.
         
         If there are no user rules, we return an empty string so the template
         contains no empty tags. Empty sections can distract or bias the model
         by implying that content is missing. In short, we replace the
         {additional_rules} placeholder with the full block or nothing—never
         just the inner contents.
         */
        let nonEmptyRules = qaltiRules?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let rulesSection: String = {
            guard let qaltiRules, nonEmptyRules else { return "" }
            let indentedRules = qaltiRules
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "        " + $0 }
                .joined(separator: "\n")
            return """
            This is extra info about test and application and rules you need to follow from the test author.
            <user_defined_rules>
            \(indentedRules)
            </user_defined_rules>
            """
        }()
        
        if let placeholderRange = content.range(of: "{additional_rules}") {
            content.replaceSubrange(placeholderRange, with: rulesSection)
        }
        
        return content
    }

    /// Generate error message for UI element not found, matching Python UIElementNotFoundError format
    static func generateUIElementNotFoundError(action: String, elementName: String) -> String {
        return "During \(action), element '\(elementName)' was not found. Make sure it is visible on the screen. If it is, try to describe it differently."
    }

    /// Generate error message for backend/server connection issues
    static func generateBackendConnectionError(action: String, elementName: String) -> String {
        return "During \(action), the backend server did not respond or the connection failed. The element identification service is currently unavailable. You will not be able to continue test execution. The user can try again later.\nElement: '\(elementName)'"
    }

    /// Generate error message for unknown/unexpected errors
    static func generateUnknownError(action: String, elementName: String) -> String {
        return "During \(action), an unexpected error occurred while trying to locate the element. Element: '\(elementName)'"
    }

    /// Generate error message when tool call is made without a comment
    static func generateMissingCommentError(toolName: String) -> String {
        return """
        Tool call "\(toolName)" was NOT executed because you did not provide a comment before calling the tool. See <comment_format> section. Provide the comment now and ALWAYS, then call any tool(s) again.
        """
    }

    static func iosFunctionDefinitions() throws -> [ChatQuery.ChatCompletionToolParam.FunctionDefinition] {
        return [
            .init(
                name: "open_app",
                description: try ToolDescriptions.openApp(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "app_name": .init(fields: [.type(.string)]),
                        "launch_arguments": .init(fields: [
                            .type(.array),
                            .items(AnyJSONSchema(fields: [.type(.string)]))
                        ]),
                        "launch_environment": .init(fields: [
                            .type(.object)
                        ])
                    ]),
                    .required(["app_name"])
                ])
            ),
            .init(
                name: "tap",
                description: try ToolDescriptions.tap(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "element_name": .init(fields: [.type(.string)]),
                        "post_action_delay": .init(fields: [.type(.number)]),
                        "long_tap": .init(fields: [.type(.boolean)])
                    ]),
                    .required(["element_name", "post_action_delay"])
                ])
            ),
            .init(
                name: "zoom",
                description: try ToolDescriptions.zoom(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "element_name": .init(fields: [.type(.string)]),
                        "scale": .init(fields: [.type(.number)]),
                        "velocity": .init(fields: [.type(.number)]),
                        "post_action_delay": .init(fields: [.type(.number)])
                    ]),
                    .required(["element_name", "scale", "velocity", "post_action_delay"])
                ])
            ),
            .init(
                name: "wait",
                description: try ToolDescriptions.wait(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties(["duration": .init(fields: [.type(.number)])]),
                    .required(["duration"])
                ])
            ),
            .init(
                name: "move_finger",
                description: try ToolDescriptions.move_finger(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "element_name": .init(fields: [.type(.string)]),
                        "direction": .init(fields: [
                            .type(.string),
                            .enumValues(["up", "down", "left", "right"])
                        ]),
                        "amount": .init(fields: [.type(.number)]),
                        "post_action_delay": .init(fields: [.type(.number)])
                    ]),
                    .required(["element_name", "direction", "amount", "post_action_delay"])
                ])
            ),
            .init(
                name: "open_url",
                description: try ToolDescriptions.openUrl(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "url": .init(fields: [.type(.string)]),
                        "post_action_delay": .init(fields: [.type(.number)])
                    ]),
                    .required(["url", "post_action_delay"])
                ])
            ),
            .init(
                name: "input",
                description: try ToolDescriptions.input(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties(["text": .init(fields: [.type(.string)])]),
                    .required(["text"])
                ])
            ),
            .init(
                name: "clear_input_field",
                description: try ToolDescriptions.clearInputField(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([:]),
                    .required([])
                ])
            ),
            .init(
                name: "screenshot",
                description: try ToolDescriptions.screenshot(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([:]),
                    .required([])
                ])
            ),
            .init(
                name: "shake",
                description: try ToolDescriptions.shake(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([:]),
                    .required([])
                ])
            ),
            .init(
                name: "press_button",
                description: try ToolDescriptions.press(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "button": .init(fields: [.type(.string)]),
                        "count": .init(fields: [.type(.integer)])
                    ]),
                    .required(["button"])
                ])
            ),
            .init(
                name: "run_script",
                description: try ToolDescriptions.runScript(),
                parameters: .init(fields: [
                    .type(.object),
                    .properties([
                        "script": .init(fields: [.type(.string)])
                    ]),
                    .required(["script"])
                ])
            )
        ]
    }
}
