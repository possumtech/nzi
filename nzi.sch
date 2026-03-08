<?xml version="1.0" encoding="UTF-8"?>
<sch:schema xmlns:sch="http://purl.oclc.org/dsdl/schematron">

  <!-- SESSION Rules -->
  <sch:pattern id="session-structure">
    <sch:rule context="session">
      <!-- Ensure the constitution is established in the first turn -->
      <sch:assert test="turn[@id='0']/system">
        Turn 0 must contain the system constitution.
      </sch:assert>
    </sch:rule>
  </sch:pattern>

  <!-- TURN Rules -->
  <sch:pattern id="turn-rules">
    <sch:rule context="turn">
      <sch:assert test="@id >= 0">Turn IDs must be non-negative.</sch:assert>
      <sch:assert test="count(user) = 1">Every turn must have exactly one user envelope.</sch:assert>
      <sch:assert test="count(assistant) &lt;= 1">Every turn must have 0 or 1 assistant envelopes.</sch:assert>
    </sch:rule>
    
    <sch:rule context="user">
      <sch:assert test="ask or instruct or shell or error or answer">
        Every user envelope must contain a valid interaction tag (ask, instruct, shell, error, or answer).
      </sch:assert>
    </sch:rule>

    <!-- The "Ask" Constraint: Inquiry-only turns cannot perform destructive actions -->
    <sch:rule context="turn[user/ask]/assistant/content">
      <sch:assert test="not(edit or create or delete or shell or choice)">
        An inquiry (ask) turn cannot be answered with state-changing model actions (edit, shell, choice, etc.), but may use discovery tools (read, grep, env).
      </sch:assert>
    </sch:rule>

    <!-- The "Payload" Constraint: Feedback tags require a selection -->
    <sch:rule context="shell | error">
      <sch:assert test="selection">
        Shell and Error tags must contain a selection payload.
      </sch:assert>
    </sch:rule>
  </sch:pattern>


  <!-- ACTION Rules (Enforced only in assistant/content envelope) -->
  <sch:pattern id="action-contracts">
    <!-- Surgical Edits -->
    <sch:rule context="assistant/content/edit">
      <sch:assert test="@file">Edit blocks must specify a target file.</sch:assert>
      <sch:assert test="contains(., '&lt;&lt;&lt;&lt;&lt;&lt;&lt;') and contains(., '=======') and contains(., '&gt;&gt;&gt;&gt;&gt;&gt;&gt;')">
        Edit blocks must use the unified diff format (SEARCH/REPLACE).
      </sch:assert>
    </sch:rule>

    <!-- Shell Execution -->
    <sch:rule context="assistant/content/shell | assistant/content/env">
      <sch:assert test="string-length(normalize-space(.)) &gt; 0">
        Shell/Env commands cannot be empty.
      </sch:assert>
    </sch:rule>

    <!-- Context Ownership -->
    <sch:rule context="edit | create | read | delete | shell | env | grep | choice | error | summary | response">
      <sch:assert test="ancestor::assistant">
        Model actions and protocol tags are only valid within the assistant envelope.
      </sch:assert>
    </sch:rule>

    <!-- File-based Action Validation -->
    <sch:rule context="assistant/content/edit | assistant/content/create | assistant/content/read | assistant/content/delete">
      <sch:assert test="@file">This action must specify a target file via the 'file' attribute.</sch:assert>
    </sch:rule>
  </sch:pattern>

</sch:schema>
