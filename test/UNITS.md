# NZI Unit Testing Roadmap

This document outlines the complete set of unit tests required to verify the integrity, fidelity, and robustness of the NZI protocol. Each unit consists of an XML turn (`test/turns/`) and a corresponding live Python drill (`test/units/`).

## 1. Core Discovery Protocol (Read-Only)
- [x] **unit_read_basic**: Verify Character-perfect `<read />` of a text file.
- [x] **unit_lookup_basic**: Verify `<lookup>` returns expected matches across multiple files.
- [x] **unit_env_basic**: Verify `<env>` execution for non-destructive discovery (e.g., `ls -R`).
- [x] **unit_discovery_multi**: Verify multiple discovery actions in a single turn.

## 2. Modification Protocol (State-Changing)
- [ ] **unit_create_basic**: Verify `<create>` with full file content and proper escaping.
- [ ] **unit_edit_surgical**: Verify `<edit>` with a single SEARCH/REPLACE block.
- [ ] **unit_edit_multi**: Verify `<edit>` with multiple blocks in one file.
- [ ] **unit_edit_cross_file**: Verify `<edit>` across multiple files in one turn.
- [ ] **unit_shell_basic**: Verify `<shell>` execution for destructive actions.
- [ ] **unit_delete_basic**: Verify `<delete>` correctly targets and removes a file.

## 3. Protocol Constraints (Schematron/Logic)
- [ ] **unit_ask_constraint**: Verify that an `<ask>` turn fails if the model attempts state-changing actions (`edit`, `shell`, etc.).
- [ ] **unit_instruct_freedom**: Verify that `<instruct>` allows any valid combination of tools.
- [ ] **unit_user_feedback**: Verify that `<shell>` or `<error>` feedback from the user includes the required `<selection>`.

## 4. Robustness & Healing (Fidelity)
- [ ] **unit_junk_handling**: Verify that conversational filler outside of tags is correctly captured in the `<content>` node.
- [ ] **unit_broken_xml**: Verify that malformed XML from the model is healed into a readable string without crashing the DOM.
- [ ] **unit_nested_content**: Verify that model-generated redundant `<content>` or `<response>` tags are unwrapped correctly.
- [ ] **unit_reasoning_gift**: Verify that `reasoning_content` from supported models is preserved and projected into the DOM.

## 5. Interaction & Navigation
- [ ] **unit_choice_basic**: Verify the model correctly formats a `<choice>` for user interaction.
- [ ] **unit_summary_strict**: Verify the model adheres to the 80-character, one-line constraint for `<summary>`.
- [ ] **unit_answer_flow**: Verify the flow of a user `<answer>` to a model `<choice>`.

## 6. History & Context
- [ ] **unit_history_projection**: Verify that previously visited files in `<history>` are correctly projected back to the model in subsequent turns.
- [ ] **unit_roadmap_context**: Verify that the `<project_roadmap>` is correctly utilized by the model for long-term planning.
