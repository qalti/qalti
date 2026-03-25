//
//  OnboardingSamples.swift
//  Qalti
//
//  Created by AI Assistant on 02.07.2025.
//

import Foundation

/// Contains sample content and templates used during onboarding
public struct OnboardingSamples {

    /// Content for the advanced test created during advanced test onboarding step
    public static let advancedTestContent: String = """
// This is a tutorial test that shows how Qalti works
// Let's take a look at how Qalti could perform autonomously. We'll do something you can't do with any existing QA automation software: solve a word puzzle. Some people at Qalti are really into NYT's puzzle games, and we'll go with Spelling Bee.
open springboard
open safari
// Notice how you don't have to specify the exact steps like "tap the address bar", "enter the URL", etc.
go to https://www.nytimes.com/puzzles/spelling-bee
// Here a lot of stuff that would cause a normal test automation suite to flake will be handled automatically.
tap "Play"
// But sometimes you have to specify the exact behavior. There will be a full-screen ad here that doesn't initially have a "Continue" button. Qalti can delay the next step.
if you see an ad, wait 3 seconds
tap continue
//
// Let's check that the initial score is 0
//
assert: yellow circle at the top of the page contains 0
//
// This is where the magic happens. The goal of Spelling Bee is to enter words that have to contain the central yellow letter and can contain any of the gray characters around it. This is straightforward for humans, but normally a pain to automate, because every day you get a new set of characters, and their positions are random.
//
enter a 4+ letter word using characters in gray hexagons and the character in the yellow hexagon. Must contain the character in the yellow hexagon, must be a valid American English word, must not be offensive. Use 'hexagon with the letter ... in the middle' as the element name.
if you see "Love Spelling Bee?" banner, close it
if you don't see the enter button below hexagons, scroll down from the empty space on the right (to avoid tapping on the input letters)
tap Enter
// Let's check if the score has changed. We haven't specified the exact length of the word and haven't asked for a pangram (a word containing all the letters in the puzzle), and these affect the score, so we'll just check it's not 0
if you don't see the score, move finder down from the empty space on the right
assert: yellow circle at the top of the page contains a number that is not 0



"""

} 
