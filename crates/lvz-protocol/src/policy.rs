//! Per-room and per-member tool allowlists.
//!
//! One implementation for the Matrix gateway and the HTTP gateway. `None` means the turn is
//! unconstrained (the full registry). `Some(vec)` is the exact set, and an empty vec means no
//! tools. A non-empty member map fails closed for a sender who is not listed.

use std::collections::{HashMap, HashSet};

/// The tools `sender` may use in `room`.
///
/// * Both maps empty for this pair, and the member map itself empty: `None` (unconstrained).
/// * Member map non-empty and `sender` absent: `Some([])`.
/// * Only a room entry: that room's set.
/// * Only a member entry: that member's set.
/// * Both entries: the intersection.
pub fn tools_for(
    room_tools: &HashMap<String, HashSet<String>>,
    user_tools: &HashMap<String, HashSet<String>>,
    room: &str,
    sender: &str,
) -> Option<Vec<String>> {
    if !user_tools.is_empty() && !user_tools.contains_key(sender) {
        return Some(Vec::new());
    }
    let room_set = room_tools.get(room);
    let user_set = user_tools.get(sender);
    match (room_set, user_set) {
        (None, None) => None,
        (Some(r), None) => Some(r.iter().cloned().collect()),
        (None, Some(u)) => Some(u.iter().cloned().collect()),
        (Some(r), Some(u)) => Some(r.intersection(u).cloned().collect()),
    }
}

/// Same decision as [`tools_for`]. The name the confirm gate and the cancel hook use.
pub fn effective_tools(
    room_tools: &HashMap<String, HashSet<String>>,
    user_tools: &HashMap<String, HashSet<String>>,
    room: &str,
    user: &str,
) -> Option<Vec<String>> {
    tools_for(room_tools, user_tools, room, user)
}

/// Whether `tool` is inside a grant. `None` grants every tool.
pub fn tool_permitted(grant: Option<&[String]>, tool: &str) -> bool {
    match grant {
        None => true,
        Some(names) => names.iter().any(|name| name == tool),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(pairs: &[(&str, &[&str])]) -> HashMap<String, HashSet<String>> {
        pairs
            .iter()
            .map(|(k, v)| {
                (
                    (*k).to_string(),
                    v.iter().map(|s| (*s).to_string()).collect(),
                )
            })
            .collect()
    }

    fn sorted(grant: Option<Vec<String>>) -> Option<Vec<String>> {
        grant.map(|mut v| {
            v.sort();
            v
        })
    }

    #[test]
    fn policy_table_matches_the_matrix_rules() {
        let rooms = map(&[("!ops:hs", &["shell", "read_file"])]);
        let users = map(&[("@admin:hs", &["read_file", "write_file"])]);

        assert_eq!(
            sorted(tools_for(&rooms, &users, "!ops:hs", "@admin:hs")),
            Some(vec!["read_file".into()])
        );
        assert_eq!(
            sorted(tools_for(&rooms, &users, "!other:hs", "@admin:hs")),
            Some(vec!["read_file".into(), "write_file".into()])
        );
        assert_eq!(
            tools_for(&rooms, &users, "!ops:hs", "@guest:hs"),
            Some(Vec::new())
        );
        assert_eq!(
            tools_for(&rooms, &HashMap::new(), "!other:hs", "@guest:hs"),
            None
        );
        assert_eq!(
            sorted(tools_for(&rooms, &HashMap::new(), "!ops:hs", "@guest:hs")),
            Some(vec!["read_file".into(), "shell".into()])
        );
        assert_eq!(
            tools_for(&HashMap::new(), &users, "!other:hs", "@guest:hs"),
            Some(Vec::new())
        );
        assert!(effective_tools(&rooms, &users, "!ops:hs", "@admin:hs").is_some());
        assert!(tool_permitted(None, "shell"));
        assert!(!tool_permitted(Some(&[]), "shell"));
        assert!(tool_permitted(Some(&["shell".into()]), "shell"));
    }
}
