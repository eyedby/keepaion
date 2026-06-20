/**
 * Wallet Verification Engine — The Consent Stack
 */
const WalletGate = {
  generateChallengeMessage: function(walletAddress) {
    const timestamp = new Date().toISOString();
    return `Consent Stack Verification\n\nWallet: ${walletAddress}\nTimestamp: ${timestamp}\n\nI confirm ownership of this address to link my AMOK cryptographic credential.`;
  },

  requestSignature: async function() {
    const provider = window.solana || window.phantom?.solana;
    if (!provider || !provider.isPhantom) {
      alert("Verification failed: Please install and unlock Phantom wallet.");
      return null;
    }
    try {
      console.log("[WalletGate] Connecting wallet...");
      const connectionResponse = await provider.connect();
      const publicKeyStr = connectionResponse.publicKey.toString();
      
      const messageText = this.generateChallengeMessage(publicKeyStr);
      const encodedMessage = new TextEncoder().encode(messageText);

      console.log("[WalletGate] Prompting for signature...");
      const signResult = await provider.signMessage(encodedMessage, "utf8");
      
      return {
        publicKey: publicKeyStr,
        message: messageText,
        signature: Array.from(signResult.signature)
      };
    } catch (error) {
      console.error("[WalletGate] Failed:", error);
      return null;
    }
  }
};
