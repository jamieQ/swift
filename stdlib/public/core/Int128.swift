//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// MARK: - Memory layout

/// A 128-bit signed integer type.
@available(SwiftStdlib 6.0, *)
@frozen
public struct Int128: Sendable {
  //  On 64-bit platforms (including arm64_32 and any similar targets with
  //  32b pointers but HW-backed 64b integers), the layout is simply that
  //  of `Builtin.Int128`.
#if _pointerBitWidth(_64) || arch(arm64_32)
  public var _value: Builtin.Int128
  
  @_transparent
  public init(_ _value: Builtin.Int128) {
    self._value = _value
  }
  
  @usableFromInline @_transparent
  internal var _low: UInt64 {
    UInt64(truncatingIfNeeded: self)
  }
  
  @usableFromInline @_transparent
  internal var _high: Int64 {
    Int64(truncatingIfNeeded: self &>> 64)
  }
  
  @usableFromInline @_transparent
  internal init(_low: UInt64, _high: Int64) {
#if _endian(little)
    self = unsafeBitCast((_low, _high), to: Int128.self)
#else
    self = unsafeBitCast((_high, _low), to: Int128.self)
#endif
  }
  
#else
  //  On 32-bit platforms, we don't want to use Builtin.Int128 for layout
  //  because it would be 16B aligned, which is excessive for such targets
  //  (and generally incompatible with C's `_BitInt(128)`). Instead we lay
  //  out the type as two `UInt64` fields--note that we have to be careful
  //  about endianness in this case.
#if _endian(little)
  @usableFromInline internal var _low: UInt64
  @usableFromInline internal var _high: Int64
#else
  @usableFromInline internal var _high: Int64
  @usableFromInline internal var _low: UInt64
#endif
  
  @usableFromInline @_transparent
  internal init(_low: UInt64, _high: Int64) {
    self._low = _low
    self._high = _high
  }
  
  public var _value: Builtin.Int128 {
    @_transparent get { unsafeBitCast(self, to: Builtin.Int128.self) }
    @_transparent set { self = Self(newValue) }
  }
  
  @_transparent
  public init(_ _value: Builtin.Int128) {
    self = unsafeBitCast(_value, to: Self.self)
  }
#endif
  
  @_transparent
  public init(bitPattern: UInt128) {
    self.init(bitPattern._value)
  }
}

// MARK: - Constants

@available(SwiftStdlib 6.0, *)
extension Int128 {
  @_transparent
  public static var zero: Self {
    Self(Builtin.zeroInitializer())
  }
  
  @_transparent
  public static var min: Self {
    Self(_low: .zero, _high: .min)
  }
  
  @_transparent
  public static var max: Self {
    Self(_low: .max, _high: .max)
  }
}

// MARK: - Conversions from other integers

@available(SwiftStdlib 6.0, *)
extension Int128: ExpressibleByIntegerLiteral,
                  _ExpressibleByBuiltinIntegerLiteral {
  
  public typealias IntegerLiteralType = Self
  
  @_transparent
  public init(_builtinIntegerLiteral x: Builtin.IntLiteral) {
    self.init(Builtin.s_to_s_checked_trunc_IntLiteral_Int128(x).0)
  }
  
  @inlinable
  public init?<T>(exactly source: T) where T: BinaryInteger {
    guard let high = Int64(exactly: source >> 64) else { return nil }
    let low = UInt64(truncatingIfNeeded: source)
    self.init(_low: low, _high: high)
  }
  
  @inlinable
  public init<T>(_ source: T) where T: BinaryInteger {
    guard let value = Self(exactly: source) else {
      fatalError("value cannot be converted to Int128 because it is outside the representable range")
    }
    self = value
  }
  
  @inlinable
  public init<T>(clamping source: T) where T: BinaryInteger {
    guard let value = Self(exactly: source) else {
      self = source < .zero ? .min : .max
      return
    }
    self = value
  }
  
  @inlinable
  public init<T>(truncatingIfNeeded source: T) where T: BinaryInteger {
    let high = Int64(truncatingIfNeeded: source >> 64)
    let low = UInt64(truncatingIfNeeded: source)
    self.init(_low: low, _high: high)
  }
  
  @inlinable
  public init(_truncatingBits source: UInt) {
    self.init(_low: UInt64(source), _high: .zero)
  }
}

// MARK: - Conversions from Binary floating-point
@available(SwiftStdlib 6.0, *)
extension Int128 {
  @inlinable
  public init?<T>(exactly source: T) where T: BinaryFloatingPoint {
    if source.magnitude < 0x1.0p64 {
      guard let magnitude = UInt64(exactly: source.magnitude) else {
        return nil
      }
      self = Int128(_low: magnitude, _high: 0)
      if source < 0 { self = -self }
    } else {
      let highAsFloat = (source * 0x1.0p-64).rounded(.down)
      guard let high = Int64(exactly: highAsFloat) else { return nil }
      // Because we already ruled out |source| < 0x1.0p64, we know that
      // high contains at least one value bit, and so Sterbenz' lemma
      // allows us to compute an exact residual:
      guard let low = UInt64(exactly: source - 0x1.0p64*highAsFloat) else {
        return nil
      }
      self.init(_low: low, _high: high)
    }
  }
  
  @inlinable
  public init<T>(_ source: T) where T: BinaryFloatingPoint {
    guard let value = Self(exactly: source.rounded(.towardZero)) else {
      fatalError("value cannot be converted to Int128 because it is outside the representable range")
    }
    self = value
  }
}

// MARK: - Non-arithmetic utility conformances
@available(SwiftStdlib 6.0, *)
extension Int128: Equatable {
  @inlinable
  public static func ==(a: Self, b: Self) -> Bool {
    Bool(Builtin.cmp_eq_Int128(a._value, b._value))
  }
}

@available(SwiftStdlib 6.0, *)
extension Int128: Comparable {
  @inlinable
  public static func <(a: Self, b: Self) -> Bool {
    Bool(Builtin.cmp_slt_Int128(a._value, b._value))
  }
}

@available(SwiftStdlib 6.0, *)
extension Int128: Hashable {
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_low)
    hasher.combine(_high)
  }
}

// MARK: - Overflow-reporting arithmetic
@available(SwiftStdlib 6.0, *)
extension Int128 {
  @_transparent
  public func addingReportingOverflow(
    _ other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (result, overflow) = Builtin.sadd_with_overflow_Int128(
      self._value, other._value, Builtin.zeroInitializer()
    )
    return (Self(result), Bool(overflow))
  }
  
  @_transparent
  public func subtractingReportingOverflow(
    _ other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (result, overflow) = Builtin.ssub_with_overflow_Int128(
      self._value, other._value, Builtin.zeroInitializer()
    )
    return (Self(result), Bool(overflow))
  }
  
  @inline(__always)
  public func multipliedReportingOverflow(
    by other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let a = self.magnitude
    let b = other.magnitude
    let (magnitude, overflow) = a.multipliedReportingOverflow(by: b)
    if (self < 0) != (other < 0) {
      let partialValue = Self(bitPattern: 0 &- magnitude)
      return (partialValue, overflow || partialValue > 0)
    } else {
      let partialValue = Self(bitPattern: magnitude)
      return (partialValue, overflow || partialValue < 0)
    }
  }
  
  @inline(__always)
  public func dividedReportingOverflow(
    by other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    precondition(other != .zero, "Division by zero")
    if self == .min && other == -1 { return (.min, true) }
    return (Self(Builtin.sdiv_Int128(self._value, other._value)), false)
  }
  
  @inline(__always)
  public func remainderReportingOverflow(
    dividingBy other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    precondition(other != .zero, "Remainder dividing by zero.")
    if self == .min && other == -1 { return (0, true) }
    return (Self(Builtin.srem_Int128(self._value, other._value)), false)
  }
}

// MARK: - AdditiveArithmetic conformance
@available(SwiftStdlib 6.0, *)
extension Int128: AdditiveArithmetic {
  @inlinable
  public static func +(a: Self, b: Self) -> Self {
    let (result, overflow) = a.addingReportingOverflow(b)
    // On arm64, this check materializes the carryout in register, then does
    // a TBNZ, where we should get a b.cs instead. I filed rdar://115387277
    // to track this, but it only costs us one extra instruction, so we'll
    // keep it as is for now.
    precondition(!overflow)
    return result
  }
  
  @inlinable
  public static func -(a: Self, b: Self) -> Self {
    let (result, overflow) = a.subtractingReportingOverflow(b)
    precondition(!overflow)
    return result
  }
}

// MARK: - Multiplication and division
@available(SwiftStdlib 6.0, *)
extension Int128 {
  public static func *(a: Self, b: Self) -> Self {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    precondition(!overflow)
    return result
  }
  
  @inlinable
  public static func *=(a: inout Self, b: Self) { a = a * b }
  
  public static func /(a: Self, b: Self) -> Self {
    return a.dividedReportingOverflow(by: b).partialValue
  }
  
  @inlinable
  public static func /=(a: inout Self, b: Self) { a = a / b }
  
  public static func %(a: Self, b: Self) -> Self {
    return a.remainderReportingOverflow(dividingBy: b).partialValue
  }
  
  @inlinable
  public static func %=(a: inout Self, b: Self) { a = a % b }
}

// MARK: - Numeric conformance
@available(SwiftStdlib 6.0, *)
extension Int128: SignedNumeric {
  public typealias Magnitude = UInt128
  
  @inlinable
  public var magnitude: Magnitude {
    let unsignedSelf = UInt128(_value)
    return self < 0 ? 0 &- unsignedSelf : unsignedSelf
  }
}

// MARK: - BinaryInteger conformance
@available(SwiftStdlib 6.0, *)
extension Int128: BinaryInteger {
  
  @inlinable
  public var words: UInt128.Words {
    Words(_value: UInt128(_value))
  }
  
  public static func &=(a: inout Self, b: Self) {
    a._value = Builtin.and_Int128(a._value, b._value)
  }
  
  public static func |=(a: inout Self, b: Self) {
    a._value = Builtin.or_Int128(a._value, b._value)
  }
  
  public static func ^=(a: inout Self, b: Self) {
    a._value = Builtin.xor_Int128(a._value, b._value)
  }
  
  public static func &>>=(a: inout Self, b: Self) {
    let masked = b & 127
    a._value = Builtin.ashr_Int128(a._value, masked._value)
  }
  
  public static func &<<=(a: inout Self, b: Self) {
    let masked = b & 127
    a._value = Builtin.shl_Int128(a._value, masked._value)
  }
  
  public var trailingZeroBitCount: Int {
    _low == 0 ? 64 + _high.trailingZeroBitCount : _low.trailingZeroBitCount
  }
}

// MARK: - FixedWidthInteger conformance
@available(SwiftStdlib 6.0, *)
extension Int128: FixedWidthInteger, SignedInteger {
  
  @_transparent
  static public var bitWidth: Int { 128 }
  
  public var nonzeroBitCount: Int {
    _high.nonzeroBitCount &+ _low.nonzeroBitCount
  }
  
  public var leadingZeroBitCount: Int {
    _high == 0 ? 64 + _low.leadingZeroBitCount : _high.leadingZeroBitCount
  }
  
  public var byteSwapped: Self {
    return Self(_low: UInt64(bitPattern: _high.byteSwapped),
                _high: Int64(bitPattern: _low.byteSwapped))
  }
  
  @_transparent
  public static func &*(lhs: Self, rhs: Self) -> Self {
    // The default &* on FixedWidthInteger calls multipliedReportingOverflow,
    // which we want to avoid here, since the overflow check is expensive
    // enough that we wouldn't want to inline it into most callers.
    Self(Builtin.mul_Int128(lhs._value, rhs._value))
  }
}
