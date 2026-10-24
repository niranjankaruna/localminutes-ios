#!/usr/bin/env python3
"""Consume a reviewed, unpublished native ASR build; native inference is separate."""


def verify_asr_bundle(archive, manifest, lock):
    """Return the verified receipt only after the entire real bundle passes."""
    raise NotImplementedError("ASR cache verification has not been implemented")
