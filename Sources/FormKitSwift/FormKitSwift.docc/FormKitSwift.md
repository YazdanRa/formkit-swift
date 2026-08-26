# ``FormKitSwift``

Render, validate, edit, and serialize native SwiftUI JSON Schema forms.

## Overview

FormKitSwift is a public package boundary for reusable JSON Schema form behavior. It owns schema interpretation, validation integration, observable session state, native controls, generic tool-edit APIs, and customization options. Host apps provide persistence, networking, uploads, assistant sessions, telemetry, and surrounding page chrome.

Start with ``FormKitView`` for rendering and ``FormKitSession`` when you need controlled state.

## Topics

### Essentials

- <doc:CorePrinciples>
- <doc:CoreConcepts>

### Getting Started

- <doc:GettingStarted>

### Usage

- <doc:CustomizationGuide>
- <doc:SchemaDrivenComponents>
- <doc:Accessibility>

### Generic Tools

- <doc:GenericTools>

### Contributor Guide

- <doc:Contributing>

### Core Types

- ``FormKitView``
- ``FormKitSession``
- ``FormKitRenderer``
- ``FormKitRendering``
- ``FormKitOptions``
- ``FormKitJSONValue``

### Configuration

- ``FormKitMode``
- ``FormKitValidationBehavior``
- ``FormKitConditionalRenderBehavior``
- ``FormKitStyle``
- ``FormKitLabels``
- ``FormKitComponents``
- ``FormKitFieldVisualState``
- ``FormKitFieldComponentContext``
- ``FormKitArraySectionComponentContext``
- ``FormKitSectionComponentContext``

### Rendering Models

- ``FormKitRenderPlan``
- ``FormKitFieldDescriptor``
- ``FormKitArraySectionDescriptor``
- ``FormKitArrayRowDescriptor``
- ``FormKitUIComponent``
- ``FormKitConditionalRenderState``

### Upload Models

- ``FormKitUploadHandler``
- ``FormKitUploadRequest``
- ``FormKitUploadItem``
- ``FormKitUploadedAsset``

### Tool Models

- ``FormKitToolContext``
- ``FormKitToolField``
- ``FormKitToolValueSource``
- ``FormKitToolEdit``
- ``FormKitToolEditResult``
- ``FormKitRejectedEdit``
