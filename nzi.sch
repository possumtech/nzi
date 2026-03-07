<?xml version="1.0" encoding="UTF-8"?>
<sch:schema xmlns:sch="http://purl.oclc.org/dsdl/schematron">

  <!-- SESSION Rules -->
  <sch:pattern id="session-structure">
    <sch:rule context="session">
      <!-- Ensure the constitution is established in the first turn -->
      <sch:assert test="turn[@id='0']/agent/system">
        Turn 0 must contain the system constitution in the agent envelope.
      </sch:assert>
    </sch:rule>
  </sch:pattern>

  <!-- TURN Rules -->
  <sch:pattern id="turn-rules">
    <sch:rule context="turn">
      <sch:assert test="@id >= 0">Turn IDs must be non-negative.</sch:assert>
      <sch:assert test="count(agent) = 1">Every turn must have exactly one agent envelope.</sch:assert>
    </sch:rule>
    
    <sch:rule context="agent">
      <sch:assert test="user">Every agent envelope must contain a user instruction.</sch:assert>
    </sch:rule>
  </sch:pattern>


  <!-- ACTION Rules (Enforced only in assistant envelope) -->
  <sch:pattern id="action-contracts">
    <!-- Surgical Edits -->
    <sch:rule context="assistant/edit">
      <sch:assert test="@file">Edit blocks must specify a target file.</sch:assert>
      <sch:assert test="contains(., '&lt;&lt;&lt;&lt;&lt;&lt;&lt;') and contains(., '=======') and contains(., '&gt;&gt;&gt;&gt;&gt;&gt;&gt;')">
        Edit blocks must use the unified diff format (SEARCH/REPLACE).
      </sch:assert>
    </sch:rule>

    <!-- Shell Execution -->
    <sch:rule context="assistant/shell | assistant/env">
      <sch:assert test="string-length(normalize-space(.)) &gt; 0">
        Shell/Env commands cannot be empty.
      </sch:assert>
    </sch:rule>

    <!-- Context Ownership -->
    <sch:rule context="edit | create | read | delete | shell | env | grep | choice | reset">
      <sch:assert test="parent::assistant">
        Model actions are only valid within the assistant envelope.
      </sch:assert>
    </sch:rule>
  </sch:pattern>

</sch:schema>
