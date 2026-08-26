enum FormKitComponentTestFixtures {
    static let arrayCompatibilitySchema =
        """
        {
          "type": "object",
          "properties": {
            "files": {
              "type": "array",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "string",
                "format": "uri"
              }
            },
            "numbers": {
              "type": "array",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "number"
              }
            },
            "enumFiles": {
              "type": "array",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "string",
                "enum": ["a.pdf", "b.pdf"]
              }
            },
            "constFiles": {
              "type": "array",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "string",
                "const": "required.pdf"
              }
            },
            "generic": {
              "type": "array",
              "items": {
                "type": "string",
                "format": "uri"
              }
            }
          }
        }
        """

    static let multipleFileSchema =
        """
        {
          "title": "Uploads",
          "type": "object",
          "properties": {
            "attachments": {
              "type": "array",
              "title": "Attachments",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "string",
                "format": "uri",
                "title": "Attachment"
              }
            }
          }
        }
        """

    static let componentSchema =
        """
        {
          "title": "Uploads",
          "type": "object",
          "properties": {
            "license": {
              "type": "string",
              "format": "uri",
              "title": "License",
              "x-formkit-ui-component": " FILE-FIELD "
            },
            "signature": {
              "$ref": "#/$defs/signature"
            },
            "attachments": {
              "type": "array",
              "title": "Attachments",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "string",
                "format": "uri",
                "title": "Attachment"
              }
            },
            "itemAnnotatedAttachments": {
              "type": "array",
              "title": "Item Annotated Attachments",
              "minItems": 1,
              "items": {
                "type": "string",
                "format": "uri",
                "title": "Item Attachment",
                "x-formkit-ui-component": "signature-pad"
              }
            }
          },
          "$defs": {
            "signature": {
              "type": "string",
              "format": "uri",
              "title": "Signature",
              "x-formkit-ui-component": "signature-pad"
            }
          }
        }
        """
}
