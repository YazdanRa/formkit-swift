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
          "x-formkit-ui-component": "line-options-choice",
          "x-formkit-option-color-map": {"Draft": "#64748B", "Needs Review": "#D97706", "Complete": "#16A34A"},
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

    static let sectionPagesSchema = """
    {
      "type": "object",
      "title": "Room Inspection",
      "description": "One section per page. Failed answers ask for an observation.",
      "x-formkit-layout": "section-pages",
      "required": [
        "roomNumber"
      ],
      "properties": {
        "roomNumber": {
          "type": "integer",
          "title": "Room number",
          "x-formkit-order": 1
        },
        "housekeeping": {
          "type": "object",
          "title": "Housekeeping",
          "x-formkit-order": 2,
          "properties": {
            "linens": {
              "type": "string",
              "title": "Linens clean and pressed",
              "enum": [
                "Pass",
                "Failed",
                "N/A"
              ],
              "x-formkit-ui-component": "line-options-choice",
              "x-formkit-option-color-map": {
                "Pass": "#2BB8A6",
                "Failed": "#BA1A1A",
                "N/A": "#D9DADC"
              },
              "x-formkit-order": 0
            },
            "linens_observation": {
              "type": "string",
              "title": "Observation",
              "x-formkit-order": 1
            },
            "bed": {
              "type": "string",
              "title": "Bed properly made",
              "enum": [
                "Pass",
                "Failed",
                "N/A"
              ],
              "x-formkit-ui-component": "line-options-choice",
              "x-formkit-option-color-map": {
                "Pass": "#2BB8A6",
                "Failed": "#BA1A1A",
                "N/A": "#D9DADC"
              },
              "x-formkit-order": 2
            },
            "bed_observation": {
              "type": "string",
              "title": "Observation",
              "x-formkit-order": 3
            }
          },
          "allOf": [
            {
              "if": {
                "properties": {
                  "linens": {
                    "const": "Failed"
                  }
                },
                "required": [
                  "linens"
                ]
              },
              "then": {
                "required": [
                  "linens_observation"
                ]
              }
            },
            {
              "if": {
                "properties": {
                  "bed": {
                    "const": "Failed"
                  }
                },
                "required": [
                  "bed"
                ]
              },
              "then": {
                "required": [
                  "bed_observation"
                ]
              }
            }
          ]
        },
        "equipment": {
          "type": "object",
          "title": "Equipment",
          "x-formkit-order": 3,
          "properties": {
            "doorLock": {
              "type": "string",
              "title": "Door lock functioning",
              "enum": [
                "Pass",
                "Failed",
                "N/A"
              ],
              "x-formkit-ui-component": "line-options-choice",
              "x-formkit-option-color-map": {
                "Pass": "#2BB8A6",
                "Failed": "#BA1A1A",
                "N/A": "#D9DADC"
              },
              "x-formkit-order": 0
            },
            "doorLock_observation": {
              "type": "string",
              "title": "Observation",
              "x-formkit-order": 1
            },
            "television": {
              "type": "string",
              "title": "Television and remotes work",
              "enum": [
                "Pass",
                "Failed",
                "N/A"
              ],
              "x-formkit-ui-component": "line-options-choice",
              "x-formkit-option-color-map": {
                "Pass": "#2BB8A6",
                "Failed": "#BA1A1A",
                "N/A": "#D9DADC"
              },
              "x-formkit-order": 2
            },
            "television_observation": {
              "type": "string",
              "title": "Observation",
              "x-formkit-order": 3
            }
          },
          "allOf": [
            {
              "if": {
                "properties": {
                  "doorLock": {
                    "const": "Failed"
                  }
                },
                "required": [
                  "doorLock"
                ]
              },
              "then": {
                "required": [
                  "doorLock_observation"
                ]
              }
            },
            {
              "if": {
                "properties": {
                  "television": {
                    "const": "Failed"
                  }
                },
                "required": [
                  "television"
                ]
              },
              "then": {
                "required": [
                  "television_observation"
                ]
              }
            }
          ]
        },
        "electrical": {
          "type": "object",
          "title": "Electrical",
          "x-formkit-order": 4,
          "properties": {
            "lighting": {
              "type": "string",
              "title": "Lighting complete with no burned-out lamps",
              "enum": [
                "Pass",
                "Failed",
                "N/A"
              ],
              "x-formkit-ui-component": "line-options-choice",
              "x-formkit-option-color-map": {
                "Pass": "#2BB8A6",
                "Failed": "#BA1A1A",
                "N/A": "#D9DADC"
              },
              "x-formkit-order": 0
            },
            "lighting_observation": {
              "type": "string",
              "title": "Observation",
              "x-formkit-order": 1
            }
          },
          "allOf": [
            {
              "if": {
                "properties": {
                  "lighting": {
                    "const": "Failed"
                  }
                },
                "required": [
                  "lighting"
                ]
              },
              "then": {
                "required": [
                  "lighting_observation"
                ]
              }
            }
          ]
        }
      }
    }
    """
}
