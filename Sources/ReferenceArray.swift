//
//  ReferenceArray.swift
//  SKTiled
//
//  Created by Michael Fessenden.
//  Web: https://github.com/mfessenden
//  Email: michael.fessenden@gmail.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation


/// Array with reference semantics, shared between the tile data storage caches.
///
/// All access happens on the main actor, so no locking is needed.
internal final class ReferenceArray<Element> {

    internal var array: [Element] = []

    /// Number of elements in the array.
    var count: Int {
        return array.count
    }

    /// A Boolean value indicating whether the collection is empty.
    var isEmpty: Bool {
        return array.isEmpty
    }

    /// Returns a Boolean value indicating whether an element satisfies the predicate.
    func contains(where predicate: (Element) -> Bool) -> Bool {
        return array.contains(where: predicate)
    }

    /// Appends an element.
    func append(_ element: Element) {
        array.append(element)
    }

    /// Appends elements.
    func append(contentsOf elements: [Element]) {
        array += elements
    }

    /// Inserts an element at the specified position.
    func insert(_ element: Element, at index: Int) {
        array.insert(element, at: index)
    }

    /// Removes the element at the specified position and passes it to `completion`.
    func remove(at index: Int, completion: ((Element) -> Void)? = nil) {
        let element = array.remove(at: index)
        completion?(element)
    }

    /// Removes the first element that satisfies the predicate and passes it to `completion`.
    func remove(where predicate: (Element) -> Bool, completion: ((Element) -> Void)? = nil) {
        guard let index = array.firstIndex(where: predicate) else { return }
        let element = array.remove(at: index)
        completion?(element)
    }

    /// Removes all elements and passes them to `completion`.
    func removeAll(completion: (([Element]) -> Void)? = nil) {
        let elements = array
        array.removeAll()
        completion?(elements)
    }

    /// Accesses the element at the specified position if it exists.
    subscript(index: Int) -> Element? {
        get {
            return array.indices ~= index ? array[index] : nil
        }
        set {
            guard let newValue = newValue else { return }
            array[index] = newValue
        }
    }

    func filter(_ isIncluded: (Element) -> Bool) -> [Element] {
        return array.filter(isIncluded)
    }

    /// Returns the first index in which an element of the collection satisfies the given predicate.
    func index(where predicate: (Element) -> Bool) -> Int? {
        return array.firstIndex(where: predicate)
    }

    /// Returns the elements of the collection, sorted using the given predicate as the comparison between elements.
    func sorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        return array.sorted(by: areInIncreasingOrder)
    }

    /// Returns an array containing the non-nil results of calling the given transformation with each element.
    func compactMap<Elements>(_ transform: (Element) -> Elements?) -> [Elements] {
        return array.compactMap(transform)
    }

    /// Calls the given closure on each element in the same order as a for-in loop.
    func forEach(_ body: (Element) -> Void) {
        array.forEach(body)
    }
}


extension ReferenceArray: Hashable {

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    static func == (lhs: ReferenceArray<Element>, rhs: ReferenceArray<Element>) -> Bool {
        return lhs === rhs
    }
}


extension ReferenceArray: Sequence {

    func makeIterator() -> IndexingIterator<[Element]> {
        return array.makeIterator()
    }
}


extension ReferenceArray where Element: Equatable {

    /// Returns a Boolean value indicating whether the array contains the element.
    func contains(_ element: Element) -> Bool {
        return array.contains(element)
    }
}


extension ReferenceArray: CustomStringConvertible, CustomDebugStringConvertible {

    /// A textual representation of the array and its elements.
    var description: String {
        return array.description
    }

    var debugDescription: String {
        return description
    }
}
