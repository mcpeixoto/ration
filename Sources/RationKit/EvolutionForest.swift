import Foundation

/// The evolution graph behind the set, resolved once from the printed lore.
///
/// `CreatureLore.evolvesFrom` is a *display name* — "Loop", not `loopet` — because
/// it was authored to be printed on a card, not walked. This resolves those names
/// to ids and hands back a forest: fifteen roots, every one of the fifty creatures
/// reachable, no cycles. Nothing here reads usage; it is a pure function of the
/// compiled-in set, built once.
///
/// A creature has at most one parent, so the graph really is a forest and every
/// leaf belongs to exactly one root. That is what lets a filed final be recorded
/// as a bare id instead of a (root, final) pair.
public struct EvoNode: Sendable, Equatable, Identifiable {
    public let id: String
    public let children: [EvoNode]

    public var isLeaf: Bool { children.isEmpty }

    /// Forms along the longest path from here, counting this one. A creature with
    /// no children is 1; Loop is 3.
    public var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }

    /// Every leaf reachable from here, in set order.
    public var finalIDs: [String] {
        children.isEmpty ? [id] : children.flatMap(\.finalIDs)
    }

    /// The subtree rooted at `id`, if it is at or below this node.
    public func node(_ id: String) -> EvoNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(id) { return found }
        }
        return nil
    }
}

public enum EvolutionForest {

    /// What the build had to ignore. Empty on a healthy set — `EvolutionForestTests`
    /// is what keeps it that way, since the app cannot refuse to launch over a
    /// mistyped name and silently dropping one would hide the mistake for a release.
    public struct Diagnostics: Sendable, Equatable {
        /// `evolvesFrom` names that match no creature. The child becomes a root.
        public var unresolvedParents: [String: String] = [:]
        /// Display names used by more than one creature, so a name cannot address one.
        public var ambiguousNames: [String] = []
        /// Links dropped because following them would loop. The child becomes a root.
        public var brokenCycles: [String] = []

        public var isClean: Bool {
            unresolvedParents.isEmpty && ambiguousNames.isEmpty && brokenCycles.isEmpty
        }
    }

    // MARK: Built once

    private static let built = build()

    /// The roots, in set order.
    public static var roots: [EvoNode] { built.roots }
    public static var diagnostics: Diagnostics { built.diagnostics }

    /// The subtree rooted at this creature.
    public static func node(_ id: String) -> EvoNode? { built.nodes[id] }

    /// The root of the line this creature belongs to.
    public static func root(of id: String) -> EvoNode? {
        built.rootOf[id].flatMap { built.nodes[$0] }
    }

    /// Root first, this creature last. `nil` if the creature is not in the set.
    public static func lineage(to id: String) -> [String]? { built.lineage[id] }

    /// Every leaf reachable from this creature, in set order.
    public static func finals(of id: String) -> [String] { built.nodes[id]?.finalIDs ?? [] }

    /// Every creature at or below this one — the ids a run down this line can file.
    public static func reachable(from id: String) -> [String] {
        guard let node = built.nodes[id] else { return [] }
        var out: [String] = []
        var stack = [node]
        while let next = stack.popLast() {
            out.append(next.id)
            stack.append(contentsOf: next.children)
        }
        return out
    }

    // MARK: Planning a run

    /// The whole path a run will take, decided the moment a pack is ripped.
    ///
    /// At each fork, prefer the children that still lead to a final nobody has filed —
    /// this is what makes the set completable without making the early pulls
    /// predictable. Once a line is exhausted the preference falls away and any branch
    /// will do, so a favourite line can still be replayed for a shiny.
    ///
    /// `floor`, when given, restricts every choice to branches that can still reach a
    /// final of at least that rarity. That is how a guaranteed pack keeps its promise:
    /// the roll is narrowed up front rather than rolled and thrown away.
    public static func plan(
        from rootID: String,
        avoiding filed: Set<String>,
        atLeast floor: CreatureRarity? = nil,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        guard var node = built.nodes[rootID] else { return [rootID] }
        var path = [node.id]
        while !node.children.isEmpty {
            guard let next = step(from: node, avoiding: filed, atLeast: floor, using: &rng) else {
                break
            }
            path.append(next.id)
            node = next
        }
        return path
    }

    /// One fork's worth of the same choice, for repairing a saved path whose plan no
    /// longer fits the tree.
    public static func step(
        from node: EvoNode,
        avoiding filed: Set<String>,
        atLeast floor: CreatureRarity? = nil,
        using rng: inout some RandomNumberGenerator
    ) -> EvoNode? {
        let qualifying =
            floor.map { tier in
                node.children.filter { child in
                    child.finalIDs.contains { rarity($0) >= tier }
                }
            } ?? node.children
        // A floor that nothing satisfies means the caller narrowed the root wrong.
        // Fall back to the full set rather than stalling the run mid-line.
        let eligible = qualifying.isEmpty ? node.children : qualifying
        guard !eligible.isEmpty else { return nil }
        let fresh = eligible.filter { child in
            child.finalIDs.contains { !filed.contains($0) }
        }
        let pool = fresh.isEmpty ? eligible : fresh
        return pool[Int(rng.next(upperBound: UInt64(pool.count)))]
    }

    /// Roots that can still reach a final of at least this rarity — the candidate list
    /// a guaranteed pack rolls from.
    public static func roots(reaching tier: CreatureRarity) -> [EvoNode] {
        roots.filter { root in root.finalIDs.contains { rarity($0) >= tier } }
    }

    /// The best final this line can produce. Drives nothing in the roll; useful for
    /// telling a player what a line is worth once they have finished it.
    public static func bestFinal(of id: String) -> CreatureRarity? {
        finals(of: id).map(rarity).max()
    }

    private static func rarity(_ id: String) -> CreatureRarity {
        built.rarity[id] ?? .common
    }

    // MARK: Build

    private struct Built: Sendable {
        var roots: [EvoNode] = []
        var nodes: [String: EvoNode] = [:]
        var rootOf: [String: String] = [:]
        var lineage: [String: [String]] = [:]
        var rarity: [String: CreatureRarity] = [:]
        var diagnostics = Diagnostics()
    }

    private static func build() -> Built {
        var out = Built()
        let roster = Dex.roster
        for creature in roster { out.rarity[creature.id] = creature.rarity }

        // Display name → id. A name shared by two creatures cannot address either, so
        // drop it from the index and say so rather than letting the last one win.
        var byName: [String: String] = [:]
        var seenTwice: Set<String> = []
        for creature in roster {
            if byName.updateValue(creature.id, forKey: creature.name) != nil {
                seenTwice.insert(creature.name)
            }
        }
        for name in seenTwice { byName.removeValue(forKey: name) }
        out.diagnostics.ambiguousNames = seenTwice.sorted()

        // Resolve the printed parent name to an id.
        var parent: [String: String] = [:]
        for creature in roster {
            guard let printed = Dex.lore[creature.id]?.evolvesFrom, !printed.isEmpty else {
                continue
            }
            guard let parentID = byName[printed], parentID != creature.id else {
                out.diagnostics.unresolvedParents[creature.id] = printed
                continue
            }
            parent[creature.id] = parentID
        }

        // Break any cycle by dropping the link that closes it, so the walk below
        // terminates whatever the data says.
        for creature in roster {
            var seen: Set<String> = [creature.id]
            var walker = creature.id
            while let up = parent[walker] {
                if seen.contains(up) {
                    parent.removeValue(forKey: walker)
                    out.diagnostics.brokenCycles.append(walker)
                    break
                }
                seen.insert(up)
                walker = up
            }
        }
        out.diagnostics.brokenCycles.sort()

        var children: [String: [String]] = [:]
        for creature in roster {
            guard let up = parent[creature.id] else { continue }
            children[up, default: []].append(creature.id)
        }

        func assemble(_ id: String) -> EvoNode {
            EvoNode(id: id, children: (children[id] ?? []).map(assemble))
        }

        out.roots = roster.filter { parent[$0.id] == nil }.map { assemble($0.id) }

        for root in out.roots {
            var stack: [(EvoNode, [String])] = [(root, [root.id])]
            while let (node, path) = stack.popLast() {
                out.nodes[node.id] = node
                out.rootOf[node.id] = root.id
                out.lineage[node.id] = path
                for child in node.children { stack.append((child, path + [child.id])) }
            }
        }
        return out
    }
}
