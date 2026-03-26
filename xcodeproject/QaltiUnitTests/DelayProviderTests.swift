//
//  DelayProviderTests.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import XCTest
@testable import Qalti

final class DelayProviderTests: XCTestCase {

    func testMockDelayProviderTracking() {
        let mockProvider = MockDelayProvider()
        
        // Initially no calls
        XCTAssertEqual(mockProvider.delayCallCount, 0)
        XCTAssertNil(mockProvider.lastDelayInterval)
        XCTAssertTrue(mockProvider.allDelayIntervals.isEmpty)
        XCTAssertEqual(mockProvider.totalDelayTime, 0.0)
    }
    
    func testMockDelayProviderSingleCall() async {
        let mockProvider = MockDelayProvider()
        
        let startTime = Date()
        try? await mockProvider.delay(2.5)
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Mock should return immediately (no actual delay)
        XCTAssertLessThan(elapsed, 0.1, "Mock delay should be near-instant")
        
        // Check tracking
        XCTAssertEqual(mockProvider.delayCallCount, 1)
        XCTAssertEqual(mockProvider.lastDelayInterval, 2.5)
        XCTAssertEqual(mockProvider.allDelayIntervals, [2.5])
        XCTAssertEqual(mockProvider.totalDelayTime, 2.5)
    }
    
    func testMockDelayProviderMultipleCalls() async {
        let mockProvider = MockDelayProvider()
        
        try? await mockProvider.delay(1.0)
        try? await mockProvider.delay(2.0)
        try? await mockProvider.delay(4.0)
        
        XCTAssertEqual(mockProvider.delayCallCount, 3)
        XCTAssertEqual(mockProvider.lastDelayInterval, 4.0)
        XCTAssertEqual(mockProvider.allDelayIntervals, [1.0, 2.0, 4.0])
        XCTAssertEqual(mockProvider.totalDelayTime, 7.0)
    }
    
    func testMockDelayProviderReset() async {
        let mockProvider = MockDelayProvider()
        
        try? await mockProvider.delay(5.0)
        XCTAssertEqual(mockProvider.delayCallCount, 1)
        
        mockProvider.reset()
        
        XCTAssertEqual(mockProvider.delayCallCount, 0)
        XCTAssertNil(mockProvider.lastDelayInterval)
        XCTAssertTrue(mockProvider.allDelayIntervals.isEmpty)
        XCTAssertEqual(mockProvider.totalDelayTime, 0.0)
    }
    
    func testMockDelayProviderActualDelay() async {
        let mockProvider = MockDelayProvider()
        mockProvider.shouldActuallyDelay = true
        
        let startTime = Date()
        try? await mockProvider.delay(0.1) // Short delay for test
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should actually delay when flag is set
        XCTAssertGreaterThan(elapsed, 0.05, "Should actually delay when flag is set")
        
        // But still track the call
        XCTAssertEqual(mockProvider.delayCallCount, 1)
        XCTAssertEqual(mockProvider.lastDelayInterval, 0.1)
    }
    
    func testMockDelayProviderDelayOverride() async {
        let mockProvider = MockDelayProvider()
        mockProvider.shouldActuallyDelay = true
        mockProvider.delayOverride = 0.05 // Override to shorter delay for test
        
        let startTime = Date()
        try? await mockProvider.delay(10.0) // Request long delay
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should use override delay, not requested delay
        XCTAssertLessThan(elapsed, 5.0, "Should use override delay")
        
        // But tracking should show requested delay
        XCTAssertEqual(mockProvider.lastDelayInterval, 10.0)
    }
    
    func testMockDelayProviderWasDelayCalledWith() async {
        let mockProvider = MockDelayProvider()
        
        try? await mockProvider.delay(2.5)
        try? await mockProvider.delay(5.0)
        
        XCTAssertTrue(mockProvider.wasDelayCalledWith(2.5))
        XCTAssertTrue(mockProvider.wasDelayCalledWith(5.0))
        XCTAssertFalse(mockProvider.wasDelayCalledWith(1.0))
        
        // Test tolerance
        XCTAssertTrue(mockProvider.wasDelayCalledWith(2.45, tolerance: 0.1))
        XCTAssertFalse(mockProvider.wasDelayCalledWith(2.3, tolerance: 0.1))
    }
    
    func testMockDelayProviderVerifyDelayProgression() async {
        let mockProvider = MockDelayProvider()
        
        try? await mockProvider.delay(1.0)
        try? await mockProvider.delay(2.0)
        try? await mockProvider.delay(4.0)
        
        // Test exact progression
        XCTAssertTrue(mockProvider.verifyDelayProgression([1.0, 2.0, 4.0]))
        
        // Test wrong progression
        XCTAssertFalse(mockProvider.verifyDelayProgression([1.0, 3.0, 4.0]))
        
        // Test wrong count
        XCTAssertFalse(mockProvider.verifyDelayProgression([1.0, 2.0]))
        
        // Test with tolerance
        XCTAssertTrue(mockProvider.verifyDelayProgression([0.95, 2.05, 3.9], tolerance: 0.15))
    }
    
    func testSystemDelayProviderActuallyDelays() async {
        let systemProvider = SystemDelayProvider()
        
        let startTime = Date()
        try? await systemProvider.delay(0.1) // Short delay for test
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should actually delay
        XCTAssertGreaterThan(elapsed, 0.05, "SystemDelayProvider should actually delay")
    }
    
    func testDelayProviderFactoryTestingEnvironment() {
        // Simulate test environment
        let provider = DelayProviderFactory.createForTesting(shouldActuallyDelay: false)
        
        XCTAssertTrue(provider is MockDelayProvider)
        XCTAssertFalse(provider.shouldActuallyDelay)
    }
    
    func testDelayProviderFactoryTestingWithActualDelay() {
        let provider = DelayProviderFactory.createForTesting(shouldActuallyDelay: true)
        
        XCTAssertTrue(provider is MockDelayProvider)
        XCTAssertTrue(provider.shouldActuallyDelay)
    }
}