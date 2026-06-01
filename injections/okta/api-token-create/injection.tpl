{
  "@timestamp": "{{ .Timestamp }}",
  "message": {
    "actor": {
      "id": "00u1lnbwklc2riVDr358",
      "type": "User",
      "alternateId": "{{ or .ActorEmail "svc-okta@replace.com" }}",
      "displayName": "{{ or .ActorDisplayName "Policy Engine" }}",
      "detailEntry": null
    },
    "client": {
      "userAgent": {
        "rawUserAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
        "os": "Mac OS 15.7.4 (Sequoia)",
        "browser": "CHROME"
      },
      "zone": "null",
      "device": "Computer",
      "id": null,
      "ipAddress": "134.238.233.62",
      "geographicalContext": {
        "city": "Portland",
        "state": "Oregon",
        "country": "United States",
        "postalCode": "97204",
        "geolocation": {
          "lat": 45.5248,
          "lon": -122.6789
        }
      }
    },
    "device": null,
    "authenticationContext": {
      "authenticationProvider": null,
      "credentialProvider": null,
      "credentialType": null,
      "issuer": null,
      "interface": null,
      "authenticationStep": 0,
      "externalSessionId": "102t3DwSsTqTcy4rn7Ui4-eTw",
      "rootSessionId": "102t3DwSsTqTcy4rn7Ui4-eTw"
    },
    "displayMessage": "Create API token",
    "eventType": "system.api_token.create",
    "outcome": {
      "result": "SUCCESS",
      "reason": null
    },
    "published": "{{ .Timestamp }}",
    "securityContext": {
      "asNumber": 394089,
      "asOrg": "palo alto networks  inc",
      "isp": "google",
      "domain": null,
      "isProxy": false
    },
    "severity": "INFO",
    "debugContext": {
      "debugData": {
        "requestId": "73a6719e43c09e3a6cdfb42b1e96fd8f",
        "dtHash": "8c83619dfa60b05d4270a587692a84dfc12302ec46cce761481bf9a06025acb3",
        "risk": "{reasons=Anomalous Location, level=MEDIUM}",
        "requestUri": "/api/internal/tokens",
        "url": "/api/internal/tokens?expand=user"
      }
    },
    "legacyEventType": "core.user.api_token.create",
    "transaction": {
      "type": "WEB",
      "id": "73a6719e43c09e3a6cdfb42b1e96fd8f",
      "detail": {}
    },
    "uuid": "{{ .ExecutionID }}",
    "version": "0",
    "request": {
      "ipChain": [
        {
          "ip": "134.238.233.62",
          "geographicalContext": {
            "city": "Portland",
            "state": "Oregon",
            "country": "United States",
            "postalCode": "97204",
            "geolocation": {
              "lat": 45.5248,
              "lon": -122.6789
            }
          },
          "version": "V4",
          "source": null
        }
      ]
    },
    "target": [
      {
        "id": "00T6rxz11gtscviV4357",
        "type": "Token",
        "alternateId": "unknown",
        "displayName": "simrun-test-api-token",
        "detailEntry": null
      }
    ]
  }
}
