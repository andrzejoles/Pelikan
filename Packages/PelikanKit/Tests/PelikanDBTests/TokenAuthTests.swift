import Foundation
@testable import PelikanDB
import Testing

@Suite("Uwierzytelnianie tokenem (Entra ID, OAuth2) — connect string")
struct TokenAuthTests {
    let entra = TokenAuth(flow: .azureInteractive, tenantID: "t-1", clientID: "c-2", appIDURI: "https://example.invalid/app")

    @Test("Parametry przepływów i brakujące pola")
    func parameters() {
        #expect(entra.parameters.map(\.0) == ["TOKEN_AUTH", "TENANT_ID", "AZURE_CLIENT_ID", "AZURE_DB_APP_ID_URI"])
        #expect(entra.missingFields.isEmpty)
        #expect(TokenAuth(flow: .azureInteractive, tenantID: "x").missingFields == ["AZURE_CLIENT_ID", "AZURE_DB_APP_ID_URI"])
        let file = TokenAuth(flow: .oauthFile, tokenLocation: "/tmp/token")
        #expect(file.parameters.map(\.0) == ["TOKEN_AUTH", "TOKEN_LOCATION"] && file.parameters[0].1 == "OAUTH")
        #expect(TokenAuth(flow: .oauthFile).missingFields == ["TOKEN_LOCATION"])
        #expect(ConnectionTarget(user: "", connectString: "h/s").usesExternalCredentials == false)
        var t = ConnectionTarget(user: "", connectString: "h/s")
        t.tokenAuth = entra
        #expect(t.usesExternalCredentials)
    }

    @Test("Deskryptor: nowa i istniejąca sekcja SECURITY; EZConnect: parametry; alias — nil")
    func apply() {
        let p = [("TOKEN_AUTH", "OAUTH"), ("TOKEN_LOCATION", "/tmp/t")]
        #expect(TNSNames.applyTokenAuth("(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=h)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=s)))", parameters: p)
                == "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=h)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=s))(SECURITY=(TOKEN_AUTH=OAUTH)(TOKEN_LOCATION=/tmp/t)))")
        #expect(TNSNames.applyTokenAuth("(DESCRIPTION=(ADDRESS=(HOST=h))(SECURITY=(SSL_SERVER_DN_MATCH=yes)))", parameters: p)
                == "(DESCRIPTION=(ADDRESS=(HOST=h))(SECURITY=(TOKEN_AUTH=OAUTH)(TOKEN_LOCATION=/tmp/t)(SSL_SERVER_DN_MATCH=yes)))")
        #expect(TNSNames.applyTokenAuth("tcps://h:1522/s", parameters: p) == "tcps://h:1522/s?token_auth=OAUTH&token_location=/tmp/t")
        #expect(TNSNames.applyTokenAuth("tcps://h:1522/s?ssl_server_dn_match=on", parameters: p)?.hasSuffix("on&token_auth=OAUTH&token_location=/tmp/t") == true)
        #expect(TNSNames.applyTokenAuth("MYDB_HIGH", parameters: p) == nil)
    }
}
