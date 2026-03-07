<?xml version="1.0" encoding="UTF-8"?>
<sch:schema xmlns:sch="http://purl.oclc.org/dsdl/schematron">
  <sch:ns prefix="nzi" uri="nzi"/>
  <sch:ns prefix="agent" uri="nzi"/>
  <sch:ns prefix="model" uri="nzi"/>

  <!-- SESSION Rules -->
  <!-- Structural Integrity -->
  <sch:pattern id="session-structure">
    <sch:rule context="nzi:session">
      <sch:assert test="count(nzi:system) = 1">
        A session must contain exactly one system prompt element at the root.
      </sch:assert>
    </sch:rule>
  </sch:pattern>

  <!-- TURN Rules -->
  <sch:pattern id="turn-rules">
    <sch:rule context="nzi:turn">
      <sch:assert test="@id &gt;= 0">Turn IDs must be non-negative.</sch:assert>
      <sch:assert test="count(nzi:user) &lt;= 1">A turn can have at most one user block.</sch:assert>
      <sch:assert test="count(model:summary) &lt;= 1">A turn can have at most one summary block.</sch:assert>
    </sch:rule>
  </sch:pattern>

  <!-- ACTION Rules -->
  <sch:pattern id="action-contracts">
    <!-- Surgical Edits -->
    <sch:rule context="model:edit">
      <sch:assert test="@file">Edit blocks must specify a target file.</sch:assert>
      <sch:assert test="contains(., '&lt;&lt;&lt;&lt;&lt;&lt;&lt;') and contains(., '=======') and contains(., '&gt;&gt;&gt;&gt;&gt;&gt;&gt;')">
        Edit blocks must use the unified diff format (SEARCH/REPLACE).
      </sch:assert>
    </sch:rule>

    <!-- Shell Execution -->
    <sch:rule context="model:shell | model:env">
      <sch:assert test="string-length(normalize-space(.)) &gt; 0">
        Shell/Env commands cannot be empty.
      </sch:assert>
    </sch:rule>

    <!-- Selections -->
    <sch:rule context="agent:selection">
      <sch:assert test="@start and @end">Selections must have start and end attributes.</sch:assert>
    </sch:rule>
  </sch:pattern>

</sch:schema>
