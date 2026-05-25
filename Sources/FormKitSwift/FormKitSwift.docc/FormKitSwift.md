# ``FormKitSwift``

Render, validate, edit, and serialize native SwiftUI JSON Schema forms.

## Overview

FormKitSwift is a public package boundary for reusable JSON Schema form behavior. It owns the renderer, validation integration, observable session state, generic tool-edit APIs, and customization options. Host apps provide persistence, networking, assistant sessions, telemetry, and surrounding page chrome.

Start with ``FormKitView`` for rendering and ``FormKitSession`` when you need controlled state.

## Topics

### Getting Started

- <doc:GettingStarted>

### Customization

- <doc:CustomizationGuide>

### Generic Tools

- <doc:GenericTools>

### Core Types

- ``FormKitView``
- ``FormKitSession``
- ``FormKitRenderer``
- ``FormKitOptions``
- ``FormKitJSONValue``

### Rendering Models

- ``FormKitRenderPlan``
- ``FormKitFieldDescriptor``
- ``FormKitArraySectionDescriptor``
- ``FormKitArrayRowDescriptor``

### Tool Models

- ``FormKitToolContext``
- ``FormKitToolField``
- ``FormKitToolEdit``
- ``FormKitToolEditResult``
- ``FormKitRejectedEdit``
