enum DemoSchemas {
    static let inspectionSchema = """
    {
      "type": "object",
      "title": "Safety Inspection",
      "required": ["site", "status", "inspector"],
      "properties": {
        "site": {
          "type": "string",
          "title": "Site"
        },
        "inspector": {
          "type": "string",
          "title": "Inspector"
        },
        "status": {
          "type": "string",
          "title": "Status",
          "enum": ["Draft", "Needs Review", "Complete"]
        },
        "needs_follow_up": {
          "type": "boolean",
          "title": "Needs Follow Up"
        },
        "follow_up_notes": {
          "type": ["string", "null"],
          "title": "Follow Up Notes"
        },
        "observations": {
          "type": "array",
          "title": "Observations",
          "minItems": 1,
          "items": {
            "type": "object",
            "title": "Observation",
            "required": ["title"],
            "properties": {
              "title": {
                "type": "string",
                "title": "Title"
              },
              "severity": {
                "type": "string",
                "title": "Severity",
                "enum": ["Low", "Medium", "High"]
              },
              "resolved": {
                "type": "boolean",
                "title": "Resolved"
              }
            }
          }
        }
      },
      "if": {
        "properties": {
          "needs_follow_up": { "const": true }
        },
        "required": ["needs_follow_up"]
      },
      "then": {
        "required": ["follow_up_notes"]
      }
    }
    """

    static let inspectionInstance = """
    {
      "site": "North Yard",
      "inspector": "Ada",
      "status": "Draft",
      "needs_follow_up": true,
      "observations": [
        {
          "title": "Guard rail needs inspection",
          "severity": "Medium",
          "resolved": false
        }
      ]
    }
    """
}
