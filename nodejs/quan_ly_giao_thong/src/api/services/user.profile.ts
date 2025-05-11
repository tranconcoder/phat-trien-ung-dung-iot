import { getUserProfile } from "../repository/user.repo";

export default new (class UserProfileService {
  /* ---------------------------------------------------------- */
  /*                      Get user profile                      */
  /* ---------------------------------------------------------- */
  async getUserProfile(userId: number) {
    const user = await getUserProfile(userId);

    if (!user) {
      throw new Error("User not found");
    }

    return user;
  }
})();
