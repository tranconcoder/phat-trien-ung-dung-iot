import jwt from "jsonwebtoken";
import {
  JWT_SECRET,
  JWT_REFRESH_SECRET,
  JWT_ACCESS_EXPIRATION,
  JWT_REFRESH_EXPIRATION,
} from "../../configs/jwt.config";

interface TokenPayload {
  id: number;
  email: string;
}

class JwtService {
  generateTokens(payload: TokenPayload) {
    const accessToken = jwt.sign(payload, JWT_SECRET, {
      expiresIn: JWT_ACCESS_EXPIRATION,
    });

    const refreshToken = jwt.sign(payload, JWT_REFRESH_SECRET, {
      expiresIn: JWT_REFRESH_EXPIRATION,
    });

    return {
      accessToken,
      refreshToken,
    };
  }

  verifyAccessToken(token: string) {
    try {
      return jwt.verify(token, JWT_SECRET) as TokenPayload;
    } catch (error) {
      throw new Error("Invalid token");
    }
  }

  verifyRefreshToken(token: string) {
    return jwt.verify(token, JWT_REFRESH_SECRET) as TokenPayload;
  }
}

export default new JwtService();
