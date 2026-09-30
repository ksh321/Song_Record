#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Worker','Reviewer')][string]$Role,
    [Parameter(Mandatory)][string]$PromptFile,
    [ValidateSet('Explore','Implement','Complex','Sensitive','Escalation')][string]$Risk = 'Implement',
    [ValidateSet('None','EnvironmentOnly','RequirementsMissing','LogicError','ReviewBlocker','ComplexFailure')][string]$Finding='None',
    [ValidateRange(0,100)][int]$SameProblemFailures=0,
    [ValidateRange(0,100)][int]$MaximumReasoningFailures=0,
    [switch]$ReviewAfterUserFix
)
# Retired by explicit user instruction. No prompt read, login, or model invocation.
throw 'DELEGATION_DISABLED: Use the current task model; new CLI Worker/Reviewer sessions are retired.'
